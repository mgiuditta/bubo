#!/bin/zsh
# Nessun permesso di sistema prima della prima risposta (spec 26): Microfono, Accessibilità, Registrazione schermo e
# notifiche non provvisorie si chiedono solo dai punti d'ingresso delle loro feature, elencati qui sotto.
# Una chiamata nuova fuori elenco fa fallire il controllo: se è il punto d'ingresso giusto, aggiungi il file all'elenco.
set -euo pipefail
cd "${0:A:h}/.."

failed=0
# Nome del permesso, API che lo fanno comparire, file ammessi (separati da spazi; vuoto = nessuno ancora).
check() {
  local name=$1 pattern=$2 allowed=" $3 " file
  { grep -rlE --include='*.swift' "$pattern" Bubo Packages || true } | while read -r file; do
    [[ $allowed == *" $file "* ]] && continue
    print -u2 "permessi: $name chiesto da $file, fuori dai punti d'ingresso ammessi:"
    grep -nE "$pattern" "$file" | sed 's/^/  /' >&2
    failed=1
  done
}

# Feature 08: alla prima pressione della scorciatoia per parlare; Riunioni: quando si avvia la registrazione.
check Microfono 'AVCaptureDevice\.requestAccess|requestRecordPermission|\.inputNode' \
  "Bubo/Voice/MicrophoneAccess.swift Bubo/Voice/SpeechListener.swift Bubo/Meetings/MicrophoneTrack.swift"
# Feature 09: quando si attiva la funzione.
check Accessibilità 'AXIsProcessTrusted|kAXTrustedCheckOptionPrompt|AXUIElementCreate|CGEvent\.tapCreate|CGRequest(Post|Listen)EventAccess|IOHIDRequestAccess' ""
check "Registrazione schermo" 'CGRequestScreenCaptureAccess|SCShareableContent|SCScreenshotManager|SCStream|CGWindowListCreateImage|CGDisplayCreateImage' ""
# Automazione: la pagina del browser davanti, quando l'utente apre la Bolla per chiedere.
check Automazione 'usr/bin/osascript|NSAppleScript' "Bubo/Intake/BrowserPage.swift"
# Feature 06: le notifiche sono provvisorie, senza avviso; quelle non provvisorie solo quando l'utente le sceglie.
{ grep -rnE --include='*.swift' 'requestAuthorization\(options:' Bubo Packages || true } | { grep -v '\.provisional' || true } | while read -r line; do
  print -u2 "permessi: notifiche non provvisorie chieste da ${line%%:*}: ${line#*:}"
  failed=1
done

(( failed == 0 )) || exit 1
print "permessi: ok"
