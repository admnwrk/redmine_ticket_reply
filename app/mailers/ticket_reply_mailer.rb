class TicketReplyMailer < ActionMailer::Base
  layout false

  # files: Array von Redmine-Attachment-Objekten (NICHT mit der ActionMailer-Methode
  # #attachments verwechseln - daher heisst der Parameter "files"). Umfasst sowohl
  # bereits am Ticket vorhandene, angehakte Anhaenge als auch neu hochgeladene Dateien
  # (die inzwischen VOR dem Mailversand als echte Attachments am Ticket gespeichert
  # werden, siehe TicketRepliesController#create_and_attach_uploads).
  # inline_images: Array von (noch unattached) Redmine-Attachment-Objekten, die im
  # Text per Bildreferenz eingebunden sind (aus dem Editor-Drag&Drop) - werden als
  # echte MIME-Inline-Anhaenge (Content-ID) eingebettet, damit sie auch fuer
  # Empfaenger ohne Redmine-Zugriff direkt in der Mail sichtbar sind (nicht nur ueber
  # einen Download-Link, den ein Empfaenger hinter einer Firewall nie erreichen koennte).
  def reply(issue:, to:, subject:, body:, template:, from: nil, cc: [], bcc: [], files: [], inline_images: [], history_text: nil, body_html: nil, author: nil)
    @issue     = issue
    @body      = body.to_s
    @body_html = body_html
    @author    = author
    @marker    = setting('truncate_marker')
    @url       = issue_url_safe(issue)

    # from: kommt vom Absender-Dropdown im Formular (System-Default, mit
    # Namen/Prefix oder komplette User-Adresse); ohne Angabe wie bisher.
    from_addr = from.presence || setting('from_address').presence || Setting.mail_from
    reply_to  = setting('reply_to').presence || from_addr

    Array(files).each do |a|
      next unless a.respond_to?(:readable?) && a.readable?
      attachments[a.filename] = File.binread(a.diskfile)
    rescue StandardError => e
      Rails.logger.warn("[TicketReply] Anhang #{a.filename}: #{e.message}")
    end

    # Inline-Bilder als MIME-Content-ID-Anhaenge einbetten. Die vom Controller in
    # @body_html hinterlegten Platzhalter (tr-inline-cid-<attachment_id>) werden NICHT
    # hier, sondern erst in der View durch attachments[key].url ersetzt (siehe
    # _inline_images.html.erb) - das ist der von Rails vorgesehene Ort/Zeitpunkt fuer
    # den Aufruf, damit die Multipart/related-Struktur der Mail korrekt aufgebaut
    # wird. Eine Ersetzung schon hier (ausserhalb des View-Renderings) fuehrte dazu,
    # dass die Mail beim Empfaenger nur als roher HTML-Quelltext ankam statt gerendert.
    @inline_cid_placeholders = {}
    Array(inline_images).each do |a|
      next unless a.respond_to?(:readable?) && a.readable?
      key = "tr-inline-#{a.id}#{File.extname(a.filename.to_s)}"
      attachments.inline[key] = File.binread(a.diskfile)
      @inline_cid_placeholders["tr-inline-cid-#{a.id}"] = key
    rescue StandardError => e
      Rails.logger.warn("[TicketReply] Inline-Bild #{a.filename}: #{e.message}")
    end

    if history_text.present?
      attachments["Verlauf-Vorgang-#{issue.id}.txt"] =
        { mime_type: 'text/plain; charset=UTF-8', content: history_text }
    end

    # Hilft Mail-Clients beim Threading; die Redmine-Zuordnung laeuft ueber die #ID im Betreff.
    headers['References']        = "<redmine.issue-#{issue.id}@#{Setting.host_name}>"
    headers['X-Redmine-Issue-Id'] = issue.id.to_s

    tmpl       = template.to_s == 'internal' ? 'internal_reply' : 'external_reply'
    plain_only = Setting.plain_text_mail.to_s == '1'

    mail(to: to, cc: cc, bcc: bcc, from: from_addr, reply_to: reply_to, subject: subject) do |format|
      format.text { render tmpl }
      format.html { render tmpl } unless plain_only
    end
  end

  # Called from the HTML view templates (external_reply/internal_reply) - MUST run
  # during view rendering, not earlier in #reply, for attachments[key].url to build
  # a correctly structured multipart/related MIME message. Doing this substitution
  # outside the view (e.g. directly on @body_html inside #reply) produced a broken
  # multipart structure where the recipient saw the raw HTML source as plain text
  # instead of a rendered message.
  def resolved_body_html
    html = @body_html
    return html unless html.present? && @inline_cid_placeholders.present?
    @inline_cid_placeholders.each do |placeholder, key|
      html = html.gsub(placeholder, attachments[key].url)
    end
    html
  end
  helper_method :resolved_body_html if respond_to?(:helper_method)

  private

  def setting(key)
    Setting.plugin_redmine_ticket_reply[key].to_s
  end

  def issue_url_safe(issue)
    Rails.application.routes.url_helpers.issue_url(
      issue,
      host:     Setting.host_name,
      protocol: (Setting.protocol.presence || 'http')
    )
  rescue StandardError
    nil
  end
end
