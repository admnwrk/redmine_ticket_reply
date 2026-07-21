resources :issues, only: [] do
  resource :ticket_reply, only: %i[new create], controller: 'ticket_replies'
end

post 'issues/:issue_id/ticket_reply/preview',
     to: 'ticket_replies#preview',
     as: 'preview_issue_ticket_reply'

post 'issues/:issue_id/ticket_reply/preview_email',
     to: 'ticket_replies#preview_email',
     as: 'preview_email_issue_ticket_reply'

post 'issues/:issue_id/ticket_reply/upload',
     to: 'ticket_replies#upload_attachment',
     as: 'upload_ticket_reply_attachment'
