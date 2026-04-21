derived_data := ".build/xcode-derived"
configuration := "Release"
app_bundle := derived_data / "Build/Products" / configuration / "RedisConsole.app"

lint:
    swiftlint lint Sources

lint-fix:
    swiftlint lint --fix Sources

format:
    swift-format format -i --recursive Sources

format-check:
    swift-format lint --recursive Sources

build-release:
    xcodebuild -project RedisConsole.xcodeproj -scheme RedisConsole -configuration '{{ configuration }}' -destination 'platform=macOS' -derivedDataPath '{{ derived_data }}' -allowProvisioningUpdates build

clean:
    rm -rf .build

open: build-release
    @open '{{ app_bundle }}'

install: build-release
    @rm -rf ~/Applications/Redis\ Console.app
    @cp -R '{{ app_bundle }}' ~/Applications/Redis\ Console.app
    @echo 'Installed to ~/Applications/Redis Console.app'
