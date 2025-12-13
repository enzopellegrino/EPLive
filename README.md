# EPLive - Multi-Protocol Video Streaming App

A professional multi-platform video streaming application for macOS and iOS that captures camera video and streams it using RTMP or SRT protocols.

## Features

- ✅ **Multi-Platform Support**: Native support for both macOS and iOS
- 📹 **Camera Capture**: Real-time video capture using AVFoundation
- 🚀 **Dual Protocol Support**: RTMP (via HaishinKit) and SRT/UDP streaming
- 🎨 **Clean SwiftUI Interface**: Modern, intuitive UI for both platforms
- ⚙️ **Configurable Settings**: Adjust bitrate, select cameras, and configure stream URLs
- 🔄 **Camera Switching**: Easy camera switching on both platforms
- 🔒 **Permission Handling**: Automatic camera and microphone permission management
- 🔌 **Auto Protocol Detection**: Automatically selects the right protocol based on URL

## Requirements

- macOS 13.0+ / iOS 16.0+
- Xcode 15.0+
- Swift 5.9+
- Camera and microphone permissions
- HaishinKit (automatically installed via Swift Package Manager)

## Project Structure

```
EPLive/
├── EPLive.xcodeproj/
│   └── project.pbxproj
├── EPLive/
│   ├── EPLiveApp.swift           # Main app entry point
│   ├── Info.plist                # App configuration
│   ├── EPLive.entitlements       # App permissions
│   ├── Views/
│   │   ├── ContentView.swift     # Main streaming interface
│   │   ├── SettingsView.swift    # Settings and configuration
│   │   ├── ServerListView.swift  # SRT servers management
│   │   └── ServerEditView.swift  # Add/edit server form
│   ├── ViewModels/
│   │   └── StreamViewModel.swift # Main view model
│   ├── Models/
│   │   └── SRTServer.swift       # SRT server data model
│   ├── Services/
│   │   ├── CameraManager.swift      # AVFoundation camera handling
│   │   ├── RTMPStreamer.swift       # RTMP streaming (HaishinKit)
│   │   ├── SRTStreamer.swift        # SRT/UDP streaming implementation
│   │   ├── StreamingProtocol.swift  # Protocol abstraction layer
│   │   └── ServerManager.swift      # Server persistence & management
│   └── Assets.xcassets/          # App assets and icons
├── test_receiver.py              # Test UDP receiver script
└── README.md
```

## Building the Project

1. Open `EPLive.xcodeproj` in Xcode
2. Select your target device (iOS Simulator, macOS, or physical device)
3. Build and run (⌘R)

## Usage

### Managing SRT Servers

1. **Launch the app** and tap the gear icon to open settings
2. **Tap "Manage Servers"** to see your server list
3. **Add a server**:
   - Tap the "+" button
   - Enter a name (e.g., "Production Server")
   - Enter the URL (e.g., `srt://stream.example.com:9000` or `udp://192.168.1.100:8888`)
   - Set the bitrate (500 kbps - 10 Mbps)
   - Optionally mark as default
   - Tap "Add"
4. **Select a server** by tapping on it in the list
5. **Edit or delete** servers using swipe actions or the Edit button

### Streaming to External SRT Servers

The app can stream to any external SRT server:

1. **Cloud SRT Servers**: Use services like:
   - **Nimble Streamer** (https://wmspanel.com/nimble)
   - **Wowza Streaming Engine** (https://www.wowza.com/)
   - **SRT Gateway** (self-hosted)
   
2. **Configure the server** in the app:
   - URL format: `srt://your-server.com:9000`
   - Or UDP: `udp://your-server.com:8888`

3. **Grant camera permission** when prompted

4. **Select your server** in Settings (it will show in the header)

5. **Start streaming** by tapping the green play button

6. **Monitor status** - The app shows connection status and server name in the header

### Server URL Formats

**RTMP (Recommended for production):**
- **Format**: `rtmp://host[:port]/app/streamkey`
- **Examples**:
  - `rtmp://192.168.1.100/live/stream`
  - `rtmp://stream.example.com/live/mykey`
  - YouTube: `rtmp://a.rtmp.youtube.com/live2/YOUR_KEY`
  - Twitch: `rtmp://live.twitch.tv/app/YOUR_KEY`

**SRT/UDP (For testing or custom servers):**
- **SRT**: `srt://host:port` (e.g., `srt://stream.example.com:9000`)
- **UDP**: `udp://host:port` (e.g., `udp://192.168.1.100:8888`)
- **Local**: `srt://192.168.1.100:8888`

## Streaming Servers Setup

### RTMP Servers (Recommended)

RTMP is the industry standard for live streaming and works with most platforms:

#### YouTube Live
```
1. Go to YouTube Studio → Go Live
2. Copy your Stream URL and Stream Key
3. In EPLive: rtmp://a.rtmp.youtube.com/live2/YOUR_STREAM_KEY
```

#### Twitch
```
1. Go to Twitch Dashboard → Settings → Stream
2. Copy your Stream Key
3. In EPLive: rtmp://live.twitch.tv/app/YOUR_STREAM_KEY
```

#### Local RTMP Server (for testing)
```bash
# Using nginx-rtmp-module
docker run -d -p 1935:1935 --name rtmp tiangolo/nginx-rtmp

# In EPLive, use: rtmp://YOUR_IP/live/test

# Watch with VLC or ffplay:
ffplay rtmp://localhost/live/test
```

#### MediaMTX (Multi-protocol server)
```bash
# Download from https://github.com/bluenviron/mediamtx
./mediamtx

# Accepts RTMP on port 1935
# In EPLive: rtmp://YOUR_IP/mystream
# Watch: rtmp://YOUR_IP/mystream
```

### SRT/UDP Servers

To receive the stream, you'll need an SRT/UDP receiver. Here are some options:

### Quick Test with Included Python Script (Recommended for Testing)

```bash
# Run the test receiver
python3 test_receiver.py 8888

# In the app, use: udp://YOUR_IP:8888
# Find your IP with: ifconfig | grep "inet "
```

The script will:
- ✅ Receive UDP packets from the app
- 💾 Save the H.264 stream to a file
- 📊 Show real-time statistics
- ▶️ Can be played with `ffplay stream_*.h264` or `vlc stream_*.h264`

### Using FFmpeg as SRT/UDP Server

```bash
# Install FFmpeg with SRT support
brew install ffmpeg

# Receive UDP stream
ffmpeg -f h264 -i udp://0.0.0.0:8888 -c copy output.mp4

# Or use SRT (requires SRT-enabled FFmpeg)
ffmpeg -i srt://0.0.0.0:8888?mode=listener -c copy output.mp4
```

### Using FFplay for Live Playback

```bash
# Play UDP stream directly
ffplay -fflags nobuffer -flags low_delay -i udp://0.0.0.0:8888

# Or with SRT
ffplay -i srt://0.0.0.0:8888?mode=listener
```

### Using OBS Studio

1. Download [OBS Studio](https://obsproject.com/)
2. Add Media Source
3. Uncheck "Local File"
4. Input: `udp://0.0.0.0:8888` or `srt://0.0.0.0:8888?mode=listener`
5. Click OK

### Using VLC

1. Open VLC
2. Media → Open Network Stream
3. Enter: `udp://@:8888`
4. Play

## Testing the Stream

1. **Start the receiver** on your Mac:
   ```bash
   python3 test_receiver.py 8888
   ```

2. **Find your Mac's IP**:
   ```bash
   ifconfig | grep "inet " | grep -v 127.0.0.1
   ```

3. **In the EPLive app**:
   - Open Settings (gear icon)
   - Enter URL: `udp://YOUR_MAC_IP:8888` (e.g., `udp://192.168.1.100:8888`)
   - Tap "Done"
   - Tap the green play button to start streaming

4. **Watch the stream**:
   ```bash
   # After stopping the stream, play the recorded file
   ffplay stream_*.h264
   # or
   vlc stream_*.h264
   ```

## Implementation Details

### Camera Management (CameraManager.swift)

- Uses AVFoundation for camera capture
- Supports multiple cameras on both platforms
- Captures at 720p @ 30fps resolution
- Provides real-time video frames via delegate

### Dual Protocol System (StreamingProtocol.swift)

- **Protocol Abstraction**: Unified interface for RTMP and SRT
- **Auto-detection**: Automatically selects protocol based on URL scheme
- **RTMP URLs** (`rtmp://`, `rtmps://`) → Uses HaishinKit RTMPStreamer
- **SRT/UDP URLs** (`srt://`, `udp://`) → Uses custom SRTStreamer

### RTMP Streaming (RTMPStreamer.swift)

- Uses **HaishinKit** library for professional RTMP streaming
- Features:
  - Built-in H.264 hardware encoding
  - Automatic camera management
  - Connection handling and retry logic
  - Support for RTMP and RTMPS (secure)
  - Compatible with YouTube, Twitch, Facebook Live, etc.

### SRT Streaming (SRTStreamer.swift)

- H.264 video encoding using VideoToolbox (hardware accelerated)
- Configurable bitrate (500 kbps - 10 Mbps)
- Real-time encoding and transmission over UDP
- Automatic packet fragmentation (MTU-safe)
- H.264 parameter set extraction (SPS/PPS)
- Comprehensive logging for debugging
- Error handling and connection management

**Note**: The current implementation uses UDP sockets for reliable testing. For production use with full SRT protocol features (encryption, FEC, etc.), integrate the [libsrt](https://github.com/Haivision/srt) library.

### SwiftUI Interface

- **ContentView**: Main streaming interface with status indicators
- **SettingsView**: Configuration panel for stream and camera settings
- **Platform-specific adaptations**: Different layouts for macOS and iOS

## Permissions

The app requires the following permissions:

- **Camera**: To capture video from the device camera
- **Microphone**: To capture audio (for future audio streaming support)
- **Network**: To send data over the network

These are configured in:
- `Info.plist` (usage descriptions)
- `EPLive.entitlements` (app sandbox permissions)

## Integrating Full SRT Support

The current implementation uses basic sockets. To integrate full SRT support:

1. **Add libsrt dependency**:
   - Download [libsrt](https://github.com/Haivision/srt)
   - Build for iOS and macOS
   - Add as framework to project

2. **Create Swift wrapper**:
   ```swift
   import srt
   
   class SRTSocket {
       private var socket: SRTSOCKET
       // Implement full SRT API wrapper
   }
   ```

3. **Update SRTStreamer.swift** to use the wrapper instead of basic sockets

## Troubleshooting

### Camera Not Working
- Check camera permissions in System Settings/Privacy
- Ensure camera is not being used by another app
- Restart the app

### Connection Failed
- Verify SRT server is running and accessible
- Check firewall settings
- Ensure URL format is correct (`srt://host:port`)

### Low Quality Stream
- Increase bitrate in settings
- Check network bandwidth
- Reduce resolution if needed

## Future Enhancements

- [ ] Audio streaming support
- [ ] Recording functionality
- [ ] Multiple resolution options
- [ ] Stream statistics and monitoring
- [ ] Preview window before streaming
- [ ] Full libsrt integration
- [ ] Stream authentication
- [ ] Adaptive bitrate

## License

This project is provided as-is for educational and development purposes.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

## Support

For questions or support, please open an issue on the project repository.

---

**Built with ❤️ using Swift and SwiftUI**
