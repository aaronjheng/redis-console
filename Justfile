derived_data := ".build/xcode-derived"
build_configuration := "Release"
app_bundle := derived_data / "Build/Products" / build_configuration / "RedisConsole.app"

lint:
    swiftlint lint Sources

lint-fix:
    swiftlint lint --fix Sources

format:
    swift format --recursive --in-place Sources

format-check:
    swift format lint --recursive Sources

build:
    xcodebuild -project RedisConsole.xcodeproj \
        -scheme RedisConsole \
        -configuration '{{ build_configuration }}' \
        -derivedDataPath '{{ derived_data }}' \
        CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES build

clean:
    rm -rf .build

run: build
    @open '{{ app_bundle }}'

install: build
    @rm -rf ~/Applications/Redis\ Console.app
    @cp -R '{{ app_bundle }}' ~/Applications/Redis\ Console.app
    @echo 'Installed to ~/Applications/Redis Console.app'


