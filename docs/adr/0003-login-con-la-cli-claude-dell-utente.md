# Login con la CLI `claude` dell'utente, API key solo con consenso

Il brief voleva l'abbonamento Claude come modalità predefinita, con il credito mensile Agent SDK sempre visibile. Le ricerche hanno mostrato che il credito Agent SDK è sospeso dal 15/06/2026 e che l'uso dell'abbonamento in app di terze parti richiede l'approvazione di Anthropic, mentre tutti i concorrenti avviano il binario `claude` ufficiale intatto con il login fatto dall'utente, senza blocchi noti.

Abbiamo scelto:

- **Predefinita**: il binario `claude` intatto, con il login che l'utente fa da sé (`claude auth login`). Bubo non legge, non copia, non salva e non intermedia token; non si presenta come Claude Code. Lo stato dell'account viene solo da `claude auth status`.
- **Approvazione**: in parallelo l'autore chiede ad Anthropic l'approvazione formale per l'uso dell'abbonamento in Bubo.
- **API key**: nel Portachiavi, scelta dall'utente; passata al processo figlio solo nel suo ambiente. Al limite dell'abbonamento Bubo non passa da solo all'API key: propone aspettare il reset, cambiare modello o passare all'API key, e passa solo con consenso esplicito (si paga a consumo).
- **Uso visibile**: al posto del "credito residuo", la percentuale della finestra di 5 ore e di quella settimanale con l'orario di reset, da `rate_limit_event`, `/usage` e `claude auth status`. Mai da endpoint non documentati né dal Portachiavi.

Se Anthropic nega l'approvazione, la predefinita diventa l'API key: cambia l'onboarding, non l'architettura.
