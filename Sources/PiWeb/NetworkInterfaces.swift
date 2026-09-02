import Foundation

func getLocalIPAddresses() -> [String] {
    var addresses: [String] = ["127.0.0.1", "0.0.0.0"]
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return addresses }
    guard let firstAddr = ifaddr else { return addresses }
    
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let flags = Int32(ptr.pointee.ifa_flags)
        let addr = ptr.pointee.ifa_addr.pointee
        
        // UP and RUNNING. We can include LOOPBACK if we want (127.0.0.1 is already in).
        if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) {
            if addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    // IPv6 link-local contains %
                    if !addresses.contains(ip) && !ip.contains("%") {
                        addresses.append(ip)
                    }
                }
            }
        }
    }
    
    freeifaddrs(ifaddr)
    return addresses
}
