requires=(base brew)

build alttab from=vendor/alt-tab-macos recipe=recipes/alttab.zsh \
      artifact=DerivedData/Build/Products/Release/AltTab.app \
      app=/Applications/AltTab.app proc=AltTab
