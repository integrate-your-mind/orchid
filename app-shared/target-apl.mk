# Orchid - WebRTC P2P VPN Market (on Ethereum)
# Copyright (C) 2017-2019  The Orchid Authors

# GNU Affero General Public License, Version 3 {{{ */
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# }}}


ifeq ($(filter ldid,$(debug)),)
codesign = xattr -cr $(1) && codesign -vfs $(identity) --entitlements $(2) $(1)
else
ifneq ($(identity),)
# XXX: the ldid in homebrew doesn't actually work :(
codesign = ldid -K$(identity) -S$(2) $(1)
else
codesign = mkdir -p $(dir $(3))
endif
endif

codesign += && touch $(3)

include shared/target-all.mk

cflags += -Fflutter/bin/cache/artifacts/engine/$(platform)
lflags += -Fflutter/bin/cache/artifacts/engine/$(platform)

app := $(bundle)$(contents)/Frameworks/App.framework
embed := $(bundle)$(contents)/Frameworks/$(framework).framework

ifeq ($(target),mac)
temp := 
else
temp := ios/Flutter/AppFrameworkInfo.plist
$(temp): flutter/packages/flutter_tools/templates/app/ios.tmpl/Flutter/AppFrameworkInfo.plist
	mkdir -p $(dir $@)
	cp -f $< $@
endif

rsync := rsync -a --delete $(patsubst %,--filter "- %",.DS_Store _CodeSignature Headers Modules)

$(app)$(versions)$(resources)/Info%plist $(embed)$(versions)$(resources)/Info%plist: $(dart) $(temp)
	rm -rf $(app) $(embed)
	$(flutter) assemble \
	    -dTargetPlatform="$(platform)" \
	    -dTargetFile="lib/main.dart" \
	    -dBuildMode="$(mode)" \
	    -dIosArchs="$(default)" \
	    -dTreeShakeIcons="false" \
	    -dTrackWidgetCreation="" \
	    -dDartObfuscation="false" \
	    -dSplitDebugInfo="" \
	    -dEnableBitcode="" \
	    -dDartDefines="" \
	    -dExtraFrontEndOptions="" \
	    --output="$(bundle)$(contents)/Frameworks" \
	   "$(mode)_$(assemble)_bundle_flutter_assets"
ifeq ($(target),mac)
	rm -rf $(dir $(embed))$(framework).framework{,$(versions)}/{Headers,Modules}
else
	$(rsync) --filter '- Flutter' $(engine)/Flutter.framework $(dir $(embed))
	xcrun bitcode_strip -r $(engine)/Flutter.framework/Flutter -o $(embed)/Flutter
	lipo $(patsubst %,-extract %,$(archs)) $(embed)/Flutter -output $(embed)/Flutter
endif
	touch $(patsubst %,%$(versions)$(resources)/Info.plist,$(app) $(embed))

signed += $(app)$(versions)$(signature)
$(app)$(versions)$(signature): shared/empty.plist $(app)$(versions)$(resources)/Info.plist
	@rm -rf $(dir $@)
	$(call codesign,$(app),$<,$@)

signed += $(embed)$(versions)$(signature)
$(embed)$(versions)$(signature): shared/empty.plist $(embed)$(versions)$(resources)/Info.plist
	@rm -rf $(dir $@)
	$(call codesign,$(embed),$<,$@)


cflags += -I$(assemble)/Pods/Headers/Public

$(assemble)/Pods/Manifest.lock: $(assemble)/Podfile shared/gui/.flutter-plugins
	cd $(assemble) && pod install
	touch $@

$(output)/XCBuildData/build.db: shared/empty.plist $(assemble)/Pods/Manifest.lock
	xcodebuild -project $(assemble)/Pods/Pods.xcodeproj -alltargets -arch $(default) -sdk $(sdk) SYMROOT=$(CURDIR)/$(output)
	for framework in $(output)/Release/*/*.framework; do \
	    $(rsync) "$${framework}" "$(bundle)$(contents)/Frameworks"; \
	    framework="$(bundle)$(contents)/Frameworks/$${framework##*/}"; \
	    $(call codesign,$${framework},$<,$${framework}$(versions)$(signature)); \
	done


replace = sed -e 's/@MONOTONIC@/$(monotonic)/g; s/@VERSION@/$(version)/g; s/@REVISION@/$(revision)/g; s/@DOMAIN@/$(domain)/g; s/@NAME@/$(name)/g; s/@TEAMID@/$(teamid)/g; s/@SUPPORT@/$(support)/g' $< | if test -n "$(filter noaot,$(debug))"; then sed -e 's/^@D@/   /'; else sed -e '/^@D@/d'; fi | if $(beta); then sed -e 's/^@B@/   /'; else sed -e '/^@B@/d'; fi >$@

$(output)/ents-%.plist: ents-%.plist.in
	@mkdir -p $(dir $@)
	$(replace)
