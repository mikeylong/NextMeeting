# Meeting app routing

Both **Join meeting** buttons call `AppActions.joinMeeting`. The shared router accepts recognized HTTPS conference invitations, chooses the matching installed app by bundle identifier and registered URL scheme, and awaits the macOS open result. An unavailable app or failed native request opens the original HTTPS invitation in the default HTTPS browser. Google Meet has no native route here.

No routing code logs invitation URLs, errors, passwords, calendar data, or attendee details. Tests use synthetic links and injected openers; they never join meetings or read calendars.

## Native formats

| Provider | Native route | Preservation |
| --- | --- | --- |
| Zoom | `zoommtg://<original-host>/join?action=join&confno=<numeric-ID>` | Adds the numeric ID from `/j`, `/w`, or `/wc/join`; retains the original encoded query and fragment. |
| Microsoft Teams | Replace `https` with `msteams` | Retains the original host, encoded path, query, and fragment, including meeting context and passcodes. |
| Webex App | `webex://meet?url=<encoded-original-invitation>` | Encodes the entire original HTTPS invitation once, including opaque MTID, passwords, query parameters, and fragment. |

Zoom `/my` personal-room names, `/s` host-start links, ZAK links, conflicting native control parameters, and unrepresentable path shapes retain the original browser route. The native join format cannot resolve a vanity name or preserve a host-start action. Next Meeting does not guess a meeting number or change host authority.

The app prefers current Teams over classic Teams. Webex candidates must register the `webex` scheme; an older Meetings app without that handler uses browser fallback. Launch Services is asked for the matching bundle identifier rather than whichever app has claimed the custom scheme.

## Provider evidence checked for 1.0.2

1. [Microsoft's deep-link documentation](https://learn.microsoft.com/en-us/microsoftteams/platform/concepts/build-and-test/deep-links) documents `msteams://` and warns against prefixing it onto an HTTPS URL.
2. [Zoom's joining instructions](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0060732) identify the desktop `zoommtg` handler. The [historical desktop format](https://devforum.zoom.us/t/do-url-schemes-work-with-all-devices/19661) provides `confno` and `pwd`. Zoom staff [do not support vanity names in that format](https://devforum.zoom.us/t/url-scheme-and-personal-link-names/7830) and [recommend original start URLs for ZAK flows](https://devforum.zoom.us/t/desktop-zoommtg-access-with-zak-token/28462). The installed Zoom app registers `zoommtg`; controlled invalid links verify macOS dispatch without joining.
3. [Cisco's Webex installation documentation](https://help.webex.com/article/nw5p67g/Cisco-Webex-Teams-Installation-and-Automatic-Upgrade) links the official Apple silicon app. Webex 46.9.0.35800 registers `webex` under `Cisco-Systems.Spark`; its signed `CiscoSparkPlugin` contains the full-link prefix `webex://meet?url=`. This route was verified from the official app because Cisco's [public meeting-link instructions](https://help.webex.com/en-us/article/ga1mli) describe browser handoff. The documented [SIP calling route](https://developer.webex.com/blog/build-a-click-to-call-shortcut-using-adaptive-cards-in-webex) is a different operation and would discard opaque meeting invitation information.

macOS acceptance means the target application accepted the open request. Provider login, registration, password validation, and prejoin behavior belong to the provider. Verification uses invalid or reserved destinations and does not establish that a real meeting was joined.
