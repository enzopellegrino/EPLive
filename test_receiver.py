#!/usr/bin/env python3
"""
Simple UDP receiver for testing EPLive streaming
Usage: python3 test_receiver.py [port]
Default port: 8888
"""

import socket
import sys
from datetime import datetime

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8888
    
    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', port))
    
    print(f"🎥 EPLive Test Receiver")
    print(f"📡 Listening on port {port}")
    print(f"⏰ Started at {datetime.now().strftime('%H:%M:%S')}")
    print("-" * 50)
    
    total_bytes = 0
    packet_count = 0
    
    # Optional: save to file
    output_file = f"stream_{datetime.now().strftime('%Y%m%d_%H%M%S')}.h264"
    
    print(f"💾 Saving stream to: {output_file}")
    print("🔴 Waiting for data...")
    print("-" * 50)
    
    try:
        with open(output_file, 'wb') as f:
            while True:
                data, addr = sock.recvfrom(65535)
                
                if packet_count == 0:
                    print(f"✅ Connected from {addr[0]}:{addr[1]}")
                
                packet_count += 1
                total_bytes += len(data)
                
                # Write to file
                f.write(data)
                f.flush()
                
                # Print stats every 100 packets
                if packet_count % 100 == 0:
                    mb = total_bytes / (1024 * 1024)
                    print(f"📊 Packets: {packet_count:,} | Data: {mb:.2f} MB | Last: {len(data)} bytes")
                    
    except KeyboardInterrupt:
        print(f"\n\n{'='*50}")
        print(f"⏹️  Stopped")
        print(f"📦 Total packets: {packet_count:,}")
        print(f"💾 Total data: {total_bytes / (1024*1024):.2f} MB")
        print(f"📁 Saved to: {output_file}")
        print(f"{'='*50}")
        print(f"\n▶️  To play the stream:")
        print(f"   ffplay {output_file}")
        print(f"   or")
        print(f"   vlc {output_file}")
        
    finally:
        sock.close()

if __name__ == '__main__':
    main()
