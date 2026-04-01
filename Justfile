build_dir := ".build/release"
app_bundle := build_dir / "Redis Console.app"

build:
    swift build

run:
    swift run

lint:
    swiftlint lint Sources

lint-fix:
    swiftlint lint --fix Sources

build-release:
    swift build -c release

build-app: build-release
    @rm -rf '{{ app_bundle }}'
    @mkdir -p '{{ app_bundle }}/Contents/MacOS'
    @mkdir -p '{{ app_bundle }}/Contents/Resources'
    @cp '{{ build_dir }}/RedisConsole' '{{ app_bundle }}/Contents/MacOS/'
    @cp build/Info.plist '{{ app_bundle }}/Contents/Info.plist'
    @cp assets/redis-console.icns '{{ app_bundle }}/Contents/Resources/'
    @echo 'Done: {{ app_bundle }}'

open: build-app
    @open '{{ app_bundle }}'

install: build-app
    @rm -rf ~/Applications/Redis\ Console.app
    @cp -R '{{ app_bundle }}' ~/Applications/
    @echo 'Installed to ~/Applications/Redis Console.app'

clean:
    rm -rf .build
