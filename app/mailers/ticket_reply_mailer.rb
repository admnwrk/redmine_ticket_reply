class TicketReplyMailer < ActionMailer::Base
  layout false

  # files: Array von Redmine-Attachment-Objekten (NICHT mit der ActionMailer-
  # Methode #attachments verwechseln - daher heisst der Parameter "files").
  # uploads: Array von Hashes { filename:, content:, content_type: } aus dem Formular-Upload.
  # inline_images: Array von (unattached) Redmine-Attachment-Objekten, die im Text per
  # Bildreferenz eingebunden sind (aus dem Editor-Drag&Drop) - werden als echte MIME-
  # Inline-Anhaenge (Content-ID) eingebettet, damit sie auch fuer Empfaenger ohne
  # Redmine-Zugriff direkt in der Mail sichtbar sind (nicht nur ueber einen Download-Link).
  def reply(issue:, to:, subject:, body:, template:, from: nil, cc: [], bcc: [], files: [], uploads: [], inline_images: [], history_text: nil, body_html: nil, author: nil)
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
    # @body_html hinterlegten Platzhalter (tr-inline-cid-<attachment_id>) werden erst
    # HIER durch die echte, von ActionMailer erst beim Einbetten generierte cid:-URL
    # ersetzt - vorher ist dieser Wert schlicht nicht bekannt.
    Array(inline_images).each do |a|
      next unless a.respond_to?(:readable?) && a.readable?
      key = "tr-inline-#{a.id}#{File.extname(a.filename.to_s)}"
      attachments.inline[key] = File.binread(a.diskfile)
      next unless @body_html.present?
      @body_html = @body_html.gsub("tr-inline-cid-#{a.id}", attachments[key].url)
    rescue StandardError => e
      Rails.logger.warn("[TicketReply] Inline-Bild #{a.filename}: #{e.message}")
    end

    Array(uploads).each do |u|
      attachments[u[:filename]] = { mime_type: u[:content_type], content: u[:content] }
    rescue StandardError => e
      Rails.logger.warn("[TicketReply] Upload-Anhang #{u[:filename]}: #{e.message}")
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
