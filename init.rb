require 'redmine'

Redmine::Plugin.register :redmine_ticket_reply do
  name        'Ticket Reply (E-Mail)'
  author      'admnwrk'
  url         'https://github.com/admnwrk/redmine_ticket_reply'
  description 'Sendet aus einem Ticket heraus E-Mails an frei waehlbare Empfaenger (To/CC/BCC) ' \
              'mit eigener Vorlage fuer interne und externe Empfaenger.'
  version     '1.6.0'
  requires_redmine version_or_higher: '4.2.0'

  settings(
    default: {
      'from_address'          => '',                                       # leer => Setting.mail_from
      'reply_to'              => '',                                       # leer => wie From
      'from_display_prefix'   => '',                                       # Prefix vor dem Benutzernamen im From-Anzeigenamen
      'allow_user_full_address' => '0',                                    # erlaubt komplette Mailadresse des Users als From
      'internal_domain'       => 'mail-adresse.com',                                # Empfaenger dieser Domaene = intern
      'truncate_marker'       => '----- Bitte oberhalb dieser Linie antworten -----',
      'canned_dir'            => '',                                       # leer => <plugin>/canned
      'signature_field'       => 'E-Mail-Signatur',                        # Name des Benutzer-Custom-Fields
      'auto_append_signature' => '1',                                      # Signatur automatisch anhaengen
      'default_signature'     => '',                                       # Fallback, wenn User keine hat
      'close_status'          => '',                                       # Statusname beim Schliessen (leer => Auto)
      'own_addresses'         => '',                                       # eigene Postfaecher/Aliase (aus Reply-All entfernen)
      'journal_preview_count' => '1'                                       # letzte Journal-Eintraege unter dem Formular (1-5)
    },
    partial: 'settings/ticket_reply_settings'
  )

  project_module :ticket_reply do
    permission :send_ticket_reply, { ticket_replies: %i[new create] }
  end
end

require_relative 'lib/redmine_ticket_reply/view_hook'
require_relative 'lib/redmine_ticket_reply/contact_capture'
require_relative 'lib/redmine_ticket_reply/mail_handler_patch'

# Redmine laedt Plugins bereits INNERHALB eines to_prepare-Laufs; ein eigenes
# config.to_prepare wuerde in Produktion daher nicht mehr feuern. Deshalb hier
# direkt prependen. Idempotent, und wird bei jedem Reload (Entwicklung) erneut
# durchlaufen, weil init.rb dann neu ausgewertet wird.
unless MailHandler.included_modules.include?(RedmineTicketReply::MailHandlerPatch)
  MailHandler.prepend(RedmineTicketReply::MailHandlerPatch)
end
