module RedmineTicketReply
  # Speichert Absender/Empfaenger der zuletzt eingegangenen Mail pro Ticket.
  module ContactCapture
    module_function

    def store(issue, email)
      return unless issue.is_a?(Issue) && email
      from = Array(email.from).first.to_s.strip
      to   = Array(email.to).map { |a| a.to_s.strip }.join(', ')
      cc   = Array(email.cc).map { |a| a.to_s.strip }.join(', ')
      return if from.blank? && to.blank? && cc.blank?

      rec = TicketReplyContact.find_or_initialize_by(issue_id: issue.id)
      rec.mail_from   = from
      rec.mail_to     = to
      rec.mail_cc     = cc
      rec.source_date = (email.date rescue nil)
      rec.save
    rescue StandardError => e
      Rails.logger.warn("[TicketReply] ContactCapture: #{e.class}: #{e.message}")
    end
  end
end
