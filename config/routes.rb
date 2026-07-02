resources :issues, only: [] do
  resource :ticket_reply, only: %i[new create], controller: 'ticket_replies'
end

post 'issues/:issue_id/ticket_reply/preview',
     to: 'ticket_replies#preview',
     as: 'preview_issue_ticket_reply'
