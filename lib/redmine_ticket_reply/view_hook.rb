module RedmineTicketReply
  class ViewHook < Redmine::Hook::ViewListener
    # Fuegt unterhalb der Ticket-Details einen Button ein (Partial).
    # Wird per JS in ALLE .contextual-Leisten geklont (jeweils vor span.drdn).
    render_on :view_issues_show_details_bottom,
              partial: 'ticket_replies/issue_button'

    # JS: Reply-Aktionslink in die .contextual-Leiste(n) einbinden.
    def view_layouts_base_html_head(_context = {})
      reply_relocate_script.html_safe
    end

    private

    # Literales Heredoc: kein Ruby-Escaping, JS wird 1:1 ausgegeben.
    def reply_relocate_script
      <<~'JS'
        <script>
        (function(){
          // Reply-Aktionslink in alle .contextual-Leisten klonen, jeweils vor span.drdn.
          function relocate(){
            var wrap = document.querySelector('.redmine-reply-action');
            if (!wrap) return;
            var a = wrap.querySelector('a');
            if (!a) return;

            var bars = document.querySelectorAll('#content .contextual');
            bars.forEach(function(ctx){
              if (ctx.closest('.journal, .description, .attachments, #issue_tree, #relations, .next-prev-links')) return; // untergeordnete Leisten auslassen
              if (ctx.querySelector('.redmine-reply-link')) return; // schon eingefuegt
              var clone = a.cloneNode(true);
              clone.classList.add('redmine-reply-link');
              var drdn = ctx.querySelector('span.drdn');
              if (drdn){
                ctx.insertBefore(clone, drdn);
              } else {
                ctx.appendChild(clone);
              }
            });

            wrap.parentNode && wrap.remove();
          }

          function run(){ relocate(); }

          if (document.readyState !== 'loading') { run(); }
          else { document.addEventListener('DOMContentLoaded', run); }
          document.addEventListener('ajax:complete', function(){ relocate(); });
        })();
        </script>
      JS
    end
  end
end
