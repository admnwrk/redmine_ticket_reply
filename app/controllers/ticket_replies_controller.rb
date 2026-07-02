require 'uri'

class TicketRepliesController < ApplicationController
  before_action :find_issue, :authorize_reply

  def new
    @to       = default_recipient
    @cc       = default_cc
    @bcc      = ''
    @template = detect_template(@to)
    @subject  = mail_subject
    @body     = ''
    @canned   = canned_responses
  end

  def create
    @to       = params[:to].to_s.strip
    @cc       = params[:cc].to_s.strip
    @bcc      = params[:bcc].to_s.strip
    @template = params[:template].presence || detect_template(@to)
    @subject  = (params[:subject].presence || mail_subject).to_s.gsub(/[\r\n]+/, ' ').strip
    @body     = params[:body].to_s
    @canned   = canned_responses

    attachment_ids = Array(params[:attachment_ids]).map(&:to_i)
    files          = @issue.attachments.select { |a| attachment_ids.include?(a.id) }
    history_text   = params[:include_history].present? ? build_history_text : nil
    close_request  = params[:close_ticket].present?

    if @to.blank? || @body.strip.blank?
      flash.now[:error] = l(:error_reply_missing_fields, default: 'Empfaenger und Text sind erforderlich.')
      return render :new
    end

    # Sicherheit: jede Empfaengeradresse validieren (Format + keine
    # Steuerzeichen). Blockt fehlerhafte Sends und jegliche Header-Injection.
    bad = invalid_addresses(split_addrs(@to) + split_addrs(@cc) + split_addrs(@bcc))
    if bad.any?
      flash.now[:error] = l(:error_reply_invalid_address, list: bad.join(', '),
                            default: 'Ungueltige E-Mail-Adresse(n): %{list}')
      return render :new
    end

    @body     = apply_signature(@body)
    body_html = render_markup(@body)

    delivery = TicketReplyMailer.reply(
      issue:        @issue,
      to:           split_addrs(@to),
      cc:           split_addrs(@cc),
      bcc:          split_addrs(@bcc),
      subject:      @subject,
      body:         @body,
      body_html:    body_html,
      template:     @template,
      files:        files,
      history_text: history_text,
      author:       User.current
    )

    # Zustellfehler IMMER sichtbar machen (Rails verschluckt sie in Produktion sonst).
    message = delivery.message
    message.perform_deliveries    = true
    message.raise_delivery_errors = true

    Rails.logger.info(
      "[TicketReply] Issue ##{@issue.id}: sende von #{message.from.inspect} " \
      "an=#{split_addrs(@to).inspect} cc=#{split_addrs(@cc).inspect} bcc=#{split_addrs(@bcc).inspect} " \
      "via #{TicketReplyMailer.delivery_method} (#{TicketReplyMailer.smtp_settings[:address] rescue 'n/a'})"
    )

    delivery.deliver_now
    Rails.logger.info("[TicketReply] Issue ##{@issue.id}: gesendet, Message-ID=#{message.message_id}")

    # Mail ist raus. Notiz protokollieren und ggf. schliessen (best effort).
    note = build_send_note(files, history_text.present?, close_request)
    closed, close_error = finalize_issue(note, close_request)

    flash[:notice] = l(:notice_reply_sent, default: 'E-Mail wurde gesendet.')
    flash[:notice] = "#{flash[:notice]} #{l(:notice_ticket_closed, default: 'Ticket geschlossen.')}" if closed
    if close_request && !closed
      flash[:warning] = "#{l(:warning_close_failed, default: 'Ticket konnte nicht geschlossen werden:')} #{close_error}"
    end

    redirect_to issue_path(@issue)
  rescue StandardError => e
    Rails.logger.error("[TicketReply] FEHLER beim Senden (Issue ##{@issue&.id}): #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
    # Nur generische Meldung an den Benutzer; Details ausschliesslich im Log.
    flash.now[:error] = l(:error_reply_failed, default: 'Senden fehlgeschlagen. Details siehe Server-Log.')
    render :new
  end

  # AJAX-Vorschau: rendert den Text mit der konfigurierten Redmine-Textauszeichnung.
  def preview
    render html: render_markup(params[:body].to_s)
  rescue StandardError => e
    Rails.logger.warn("[TicketReply] preview: #{e.class}: #{e.message}")
    render plain: l(:error_preview_failed, default: 'Vorschau nicht verfuegbar.')
  end

  private

  def find_issue
    @issue   = Issue.find(params[:issue_id])
    # Sicherheit: Ticket-Ebenen-Sichtbarkeit erzwingen (die Modul-/Rechte-
    # pruefung allein deckt z. B. "nur eigene Tickets" nicht ab). Verhindert
    # das Antworten auf / Exfiltrieren von nicht sichtbaren Tickets.
    return render_403 unless @issue.visible?

    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def authorize_reply
    deny_access unless User.current.allowed_to?(:send_ticket_reply, @issue.project)
  end

  def plugin_setting(key)
    Setting.plugin_redmine_ticket_reply[key].to_s
  end

  def internal_domain
    plugin_setting('internal_domain').downcase.strip
  end

  def contact
    @contact = TicketReplyContact.find_by(issue_id: @issue.id) unless defined?(@contact)
    @contact
  end

  def own_addresses
    list  = [plugin_setting('from_address'), plugin_setting('reply_to'), Setting.mail_from.to_s]
    list += plugin_setting('own_addresses').split(/[,;]/)
    list.map { |a| a.to_s.downcase.strip }.reject(&:blank?).uniq
  end

  # Letzter Mail-Absender; sonst Autor-Mail; sonst leer.
  def default_recipient
    contact&.mail_from.presence || @issue.author&.mail.presence || ''
  end

  # Uebrige Empfaenger der letzten Mail (To + Cc) ohne eigene Postfaecher und
  # ohne den Absender selbst -> fuer Reply-All.
  def default_cc
    c = contact
    return '' unless c
    own    = own_addresses
    sender = c.mail_from.to_s.downcase.strip
    recips = split_addrs(c.mail_to.to_s) + split_addrs(c.mail_cc.to_s)
    recips.reject { |a| own.include?(a.downcase) || a.downcase == sender }
          .uniq
          .join(', ')
  end

  def detect_template(to)
    dom   = internal_domain
    addrs = split_addrs(to)
    return 'external' if dom.blank? || addrs.empty?
    addrs.all? { |a| a.downcase.end_with?("@#{dom}") } ? 'internal' : 'external'
  end

  def mail_subject
    "[#{@issue.project.name} - #{@issue.tracker.name} ##{@issue.id}] #{@issue.subject}"
  end

  def split_addrs(str)
    str.to_s.split(/[,;]/).map(&:strip).reject(&:blank?)
  end

  # Liefert die nicht valide formatierten Adressen zurueck (leeres Array = alles ok).
  # URI::MailTo::EMAIL_REGEXP ist \A..\z-verankert, schliesst Steuerzeichen
  # (CR/LF) und Header-Injection aus.
  def invalid_addresses(list)
    list.reject { |a| a.to_s.match?(URI::MailTo::EMAIL_REGEXP) }
  end

  # ---- Markup / Vorschau --------------------------------------------------
  # Rendert wie ein Ticket-Kommentar (Markdown/Textile gemaess Redmine-Einstellung).
  def render_markup(text)
    view_context.textilizable(text.to_s)
  rescue StandardError => e
    Rails.logger.warn("[TicketReply] render_markup: #{e.message}")
    ('<p>' + ERB::Util.h(text.to_s).gsub("\n", "<br>\n") + '</p>').html_safe
  end

  # ---- Textbausteine ------------------------------------------------------
  def canned_dir
    custom = plugin_setting('canned_dir').strip
    return custom if custom.present? && File.directory?(custom)
    File.join(Redmine::Plugin.find(:redmine_ticket_reply).directory, 'canned')
  rescue StandardError
    nil
  end

  def canned_responses
    dir = canned_dir
    return [] unless dir && File.directory?(dir)
    Dir.glob(File.join(dir, '*.{txt,md}')).sort.filter_map do |path|
      raw = (File.read(path, encoding: 'UTF-8') rescue nil)
      next unless raw
      label = File.basename(path, '.*').sub(/\A\d+[_-]/, '').tr('_', ' ')
      subject = nil
      body    = raw
      if raw =~ /\A\s*(?:Betreff|Subject):\s*(.+?)\r?\n(.*)\z/im
        subject = Regexp.last_match(1).strip
        body    = Regexp.last_match(2)
      end
      { label: label, subject: (subject ? substitute(subject) : nil), body: substitute(body.strip) }
    end
  end

  def substitute(text)
    map = {
      'id'               => @issue.id.to_s,
      'subject'          => @issue.subject.to_s,
      'status'           => @issue.status&.name.to_s,
      'author'           => @issue.author&.name.to_s,
      'author_firstname' => @issue.author&.firstname.to_s,
      'assignee'         => @issue.assigned_to&.name.to_s,
      'agent'            => User.current.firstname.to_s,
      'agent_name'       => User.current.name.to_s,
      'signature'        => agent_signature
    }
    text.to_s.gsub(/\{\{\s*([a-z_]+)\s*\}\}/i) { map[Regexp.last_match(1).downcase] || '' }
  end

  # ---- Signatur -----------------------------------------------------------
  def agent_signature
    field = plugin_setting('signature_field').strip
    sig   = nil
    if field.present?
      cf  = UserCustomField.find_by(name: field)
      sig = User.current.custom_field_value(cf) if cf
    end
    sig = sig.to_s.strip
    sig = plugin_setting('default_signature').to_s.strip if sig.blank?
    sig
  end

  def apply_signature(body)
    return body unless plugin_setting('auto_append_signature') == '1'
    sig = agent_signature
    return body if sig.blank? || body.include?(sig)
    "#{body.rstrip}\n\n#{sig}"
  end

  # ---- Verlauf ------------------------------------------------------------
  def build_history_text
    out = []
    out << "Verlauf zu Vorgang ##{@issue.id}: #{@issue.subject}"
    out << ('=' * 60)
    out << ''
    out << "#{user_name(@issue.author)} am #{ts(@issue.created_on)} (Beschreibung):"
    out << @issue.description.to_s.strip
    out << ''
    @issue.journals.sort_by(&:created_on).each do |j|
      next if j.private_notes?
      next if j.notes.blank?
      out << ('-' * 60)
      out << "#{user_name(j.user)} am #{ts(j.created_on)}:"
      out << j.notes.to_s.strip
      out << ''
    end
    out.join("\n")
  end

  def user_name(u)
    u ? u.name : 'Unbekannt'
  end

  def ts(time)
    time ? time.localtime.strftime('%d.%m.%Y %H:%M') : ''
  end

  # ---- Notiz + Abschluss --------------------------------------------------
  def build_send_note(files, history_attached, closing)
    note = +"_E-Mail gesendet_ (Vorlage: #{@template})\n\n"
    note << "**An:** #{@to}\n"
    note << "**CC:** #{@cc}\n"   if @cc.present?
    note << "**BCC:** #{@bcc}\n" if @bcc.present?
    note << "**Anhaenge:** #{files.map(&:filename).join(', ')}\n" if files.any?
    note << "**Verlauf angehaengt:** ja\n" if history_attached
    note << "\n#{@body}"
    note
  end

  # Ziel-Status zum Schliessen: konfigurierter Name, sonst erster erlaubter
  # geschlossener Status laut Workflow.
  def target_close_status
    allowed = @issue.new_statuses_allowed_to(User.current)
    name    = plugin_setting('close_status').strip
    if name.present?
      return allowed.detect { |s| s.name == name } || IssueStatus.find_by(name: name)
    end
    allowed.detect(&:is_closed?) || IssueStatus.where(is_closed: true).order(:position).first
  end

  # Notiz schreiben und ggf. schliessen. Schlaegt das Schliessen fehl (z. B. weil
  # das Ticket durch Abhaengigkeiten blockiert ist), bleibt die Notiz erhalten und
  # der Grund wird zurueckgegeben. Gibt [closed?, fehler_oder_nil] zurueck.
  def finalize_issue(note, close)
    status      = nil
    close_error = nil

    if close
      status = target_close_status
      if status.nil?
        close_error = l(:warning_no_close_status, default: 'kein geschlossener Status gefunden')
      elsif !@issue.new_statuses_allowed_to(User.current).include?(status)
        close_error = l(:warning_close_not_allowed, default: 'Statuswechsel nicht erlaubt') + ": #{status.name}"
        status = nil
      end
    end

    journal = @issue.init_journal(User.current, note)
    journal.notify = false
    @issue.status_id = status.id if status

    if @issue.save
      [(close && !status.nil? && close_error.nil?), close_error]
    else
      errs = @issue.errors.full_messages.join('; ')
      # Statuswechsel verwerfen, Notiz dennoch sichern
      @issue.reload
      j = @issue.init_journal(User.current, note)
      j.notify = false
      @issue.save
      [false, close_error || errs]
    end
  rescue StandardError => e
    Rails.logger.error("[TicketReply] finalize: #{e.class}: #{e.message}")
    [false, e.message]
  end
end
