Tortoro is yet another `Tor` wrapper. Now in swift!

## Requirements

- iOS 9.0+
- Xcode 8.1+
- Swift 3.1+

## Installation

Include `Tortoro` as an framework into your project.

## Usage

```swift
import Tortoro

let dataDirectory = FileManager.default.urls(for: .cachesDirectory,
                                        in: .userDomainMask).last!.appendingPathComponent("tor")

let configuration = try Configuration(dataDirectory: dataDirectory)

Tortoro.configure(configuration: configuration) { (result) in
    print("started")
}

Tortoro.addReadinessListener { (result) in
    switch result {
    case .success(let connected):
        if connected {
            print("connected")
            Tortoro.getSocksConfiguration { (result) in
                switch result {
                case .success(let config):
                    print("socks proxy \(config.host):\(config.port)")
                case .failure(let error):
                    print(error)
                }
            }
        } else {
            print("disconnected")
        }
    case .failure(let error):
        print(error)
    }
}
```

## Build

```shell
git clone --recursive https://github.com/vovasty/Tortoro.git
cd Tortoro
./bootstrap.sh
```