# Background Streaming Limitations in iOS

## 🚨 Il Problema

**iOS blocca il video encoding in background** per risparmiare batteria. Questo è un comportamento intenzionale del sistema operativo, non un bug dell'app.

### Cosa Succede:

1. **App in foreground** → ✅ Video encoding attivo, streaming funziona
2. **App in background** (Home button) → ⚠️ Video encoding SOSPESO, solo audio continua
3. **Schermo bloccato** → ⚠️ Video encoding SOSPESO, solo audio continua
4. **Ritorno in foreground** → ✅ Video encoding RIPRENDE automaticamente

## 🔧 Cosa Abbiamo Implementato

### 1. **Background Modes Configurati**
- `audio` - Permette all'audio di continuare
- `processing` - Mantiene l'app "viva"
- `fetch` - Priorità aggiuntiva

### 2. **AVAudioSession Mode: `.videoChat`**
- Dice a iOS che stiamo facendo una video chiamata
- Ottiene priorità più alta rispetto a `.default`
- **MA**: iOS sospende comunque il video encoder per batteria

### 3. **Idle Timer Disabilitato**
```swift
UIApplication.shared.isIdleTimerDisabled = true
```
- Lo schermo non si blocca automaticamente
- Utente DEVE bloccare manualmente
- Quando bloccato → video si ferma comunque

### 4. **Background Task**
- Mantiene l'app in esecuzione per ~3 minuti
- Con audio session attiva → esteso indefinitamente
- **MA**: Non impedisce la sospensione del video encoder

### 5. **Keep-Alive Monitor**
- Timer che controlla ogni 2 secondi se i frame stanno aumentando
- Rileva quando il video si ferma
- Log dettagliati per debugging

### 6. **UI Warning Banner**
- Quando l'app va in background, mostra banner arancione
- "VIDEO PAUSED - Return to app to resume"
- Si nasconde quando torna in foreground

## 📊 Comportamento Per Tipo di Sorgente

### Camera 📹
- **Foreground**: ✅ Funziona perfettamente
- **Background**: ❌ iOS BLOCCA camera per privacy (policy Apple)
- **Audio**: ✅ Continua

### Schermo 🖥️  
- **Foreground**: ✅ Funziona perfettamente
- **Background**: ❌ iOS SOSPENDE screen capture
- **Audio**: ✅ Continua

### Video Locale 🎬
- **Foreground**: ✅ Funziona perfettamente  
- **Background**: ⚠️ VIDEO ENCODER SOSPESO (iOS limitation)
- **SRT Connection**: ✅ Rimane connessa
- **Audio**: ✅ Continua
- **Quando torna foreground**: ✅ Riprende automaticamente

## 🎯 Come Larix Gestisce Questo

Larix Broadcaster probabilmente usa **Picture-in-Picture (PiP)** che:
1. Mostra una piccola finestra video
2. Mantiene il video pipeline attivo
3. Richiede implementazione complessa di `AVPictureInPictureController`

**Alternativa**: Alcune app mostrano semplicemente un avviso e chiedono all'utente di tenere l'app in foreground.

## ✅ Soluzione Attuale

### Per Ora:
1. **Idle timer disabilitato** → schermo rimane acceso durante streaming
2. **Warning banner** → utente vede quando il video è in pausa
3. **Auto-resume** → quando torna, riparte subito
4. **Lock screen info** → mostra durata e stats

### Cosa Dire all'Utente:
> ⚠️ **iOS Limitation**: Per continuare lo streaming video, mantieni l'app in foreground.
> L'audio continuerà in background, ma il video si fermerà temporaneamente.
> Tornando all'app, il video riprenderà automaticamente.

## 🚀 Possibili Miglioramenti Futuri

### 1. Picture-in-Picture (Complesso)
```swift
import AVKit

let pipController = AVPictureInPictureController(playerLayer: playerLayer)
pipController?.startPictureInPicture()
```
- Mantiene video attivo anche in background
- Mostra mini player flottante
- Richiede setup complesso

### 2. Background Video Processing (iOS 15+)
- Usare `AVAssetWriterInput` con background capability
- Potrebbe funzionare per video locale
- Da testare

### 3. Notifica Locale
- Mostra notifica "Streaming in corso - Tap per tornare"
- Facilita il ritorno all'app
- Semplice da implementare

## 📝 Log di Debug

Quando testi, vedrai nei log:

```
🌙 App entered background
⚠️ Local video streaming in background:
   iOS WILL SUSPEND VIDEO ENCODING to save battery
   Audio will continue, but video frames will STOP
   This is a system limitation, not a bug
   Solution: Keep app in foreground during streaming
⏰ Keep-alive monitor started (2s interval)
⚠️ Video encoder appears stuck in background
   Frames not increasing: 1234
   VIDEO ENCODING SUSPENDED BY iOS

☀️ App will enter foreground
✅ App back to foreground - video encoding will resume
```

## 🎬 Conclusione

**La limitazione è di iOS, non dell'app**. Abbiamo implementato:
- ✅ Tutte le best practices per background execution
- ✅ Monitoring e auto-resume
- ✅ UI feedback chiaro all'utente
- ✅ Lock screen integration

Per streaming video **ininterrotto** in background, servirebbe:
- Picture-in-Picture (complesso)
- Oppure dire all'utente di tenere app in foreground (semplice)

**Raccomandazione**: Documenta la limitazione nelle note di release e nell'help dell'app.
