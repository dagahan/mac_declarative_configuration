requires=(base brew dotfiles)

build aerospace from=vendor/AeroSpace recipe=recipes/aerospace.zsh \
      artifact=.xcbuild/Build/Products/Release/AeroSpace.app \
      app=/Applications/AeroSpace.app \
      also=.build/arm64-apple-macosx/release/aerospace:/opt/homebrew/bin/aerospace \
      proc=AeroSpace
