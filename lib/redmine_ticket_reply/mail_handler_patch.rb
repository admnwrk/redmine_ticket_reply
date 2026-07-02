module RedmineTicketReply
  # Greift From/To/Cc beim Anlegen und bei jeder Antwort-Mail ab.
  module MailHandlerPatch
    # Neues Ticket aus Mail
    def receive_issue
      issue = super
      RedmineTicketReply::ContactCapture.store(issue, @email) if issue.is_a?(Issue)
      issue
    end

    # Folge-Mail (Antwort) zu bestehendem Ticket
    def receive_issue_reply(*args)
      result   = super
      issue_id = args.first
      issue    = Issue.find_by(id: issue_id) if issue_id
      RedmineTicketReply::ContactCapture.store(issue, @email) if issue
      result
    end
  end
end
