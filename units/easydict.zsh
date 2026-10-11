requires=(base software aerospace)

build easydict from=vendor/Easydict recipe=recipes/easydict.zsh \
      artifact=DerivedData/Build/Products/Release/Easydict.app \
      app=/Applications/Easydict.app proc=Easydict

default com.izual.Easydict EZConfiguration_kAllowCrashLogKey  bool false on_workspace_down=false stop_app=Easydict
default com.izual.Easydict EZConfiguration_kAllowAnalyticsKey bool false on_workspace_down=false stop_app=Easydict
