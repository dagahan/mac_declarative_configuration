requires=(base software aerospace)

build easydict from=vendor/Easydict recipe=recipes/easydict.zsh \
      artifact=DerivedData/Build/Products/Release/Easydict.app \
      app=/Applications/Easydict.app proc=Easydict

default com.izual.Easydict EZConfiguration_kAllowCrashLogKey  bool false on_workspace_down=false stop_app=Easydict
default com.izual.Easydict EZConfiguration_kAllowAnalyticsKey bool false on_workspace_down=false stop_app=Easydict

manual easydict-accessibility \
    do="System Settings > Privacy & Security > Accessibility: remove Easydict with −, then add /Applications/Easydict.app with + (the entry left by the cask build names a signature this build does not have)" \
    detect='grep -h "accessibilityEnabled:" "$(ls -t ~/Library/Application\ Support/com.izual.Easydict/logs/app/Default/*.log | head -1)" | tail -1 | grep -q "true$"'
