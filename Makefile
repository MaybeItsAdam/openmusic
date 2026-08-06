INNO_VERSION=6.2.0
TEMP_DIR=/tmp/openmusic-tar
USR_SHARE=deb-struct/usr/share
BUNDLE_DIR=build/linux/${ARCH}/release/bundle
MIRRORLIST=${PWD}/build/mirrorlist

tar:
		mkdir -p $(TEMP_DIR)\
		&& cp -r $(BUNDLE_DIR)/* $(TEMP_DIR)\
		&& cp linux/openmusic.desktop $(TEMP_DIR)\
		&& cp assets/branding/openmusic-logo.png $(TEMP_DIR)\
		&& cp linux/io.github.MaybeItsAdam.OpenMusic.appdata.xml $(TEMP_DIR)\
		&& tar -cJf build/openmusic-linux-${VERSION}-${PKG_ARCH}.tar.xz -C $(TEMP_DIR) .\
		&& rm -rf $(TEMP_DIR)

aursrcinfo:
					 docker run -e EXPORT_SRC=1 -v ${PWD}/aur-struct:/pkg -v ${MIRRORLIST}:/etc/pacman.d/mirrorlist:ro whynothugo/makepkg

publishaur: 
					 echo '[Warning!]: you need SSH paired with AUR'\
					 && rm -rf build/openmusic\
					 && git clone ssh://aur@aur.archlinux.org/openmusic-bin.git build/openmusic\
					 && cp aur-struct/PKGBUILD aur-struct/.SRCINFO build/openmusic\
					 && cd build/openmusic\
					 && git add .\
					 && git commit -m "${MSG}"\
					 && git push

innoinstall:
						powershell curl -o build\installer.exe http://files.jrsoftware.org/is/6/innosetup-${INNO_VERSION}.exe
						powershell git clone https://github.com/DomGries/InnoDependencyInstaller.git  build\inno-depend
		 				powershell build\installer.exe /verysilent /allusers /dir=build\iscc

inno:
		 powershell .\build\iscc\iscc.exe scripts\windows-setup-creator.iss

choco:
			powershell cp dist\OpenMusic-windows-x86_64-setup.exe choco-struct\tools
			powershell choco pack .\choco-struct\openmusic.nuspec  --outputdirectory dist

apk:
		mv build/app/outputs/apk/release/app-release.apk build/OpenMusic-android-all-arch.apk

gensums:
				sh -c scripts/gensums.sh

migrate:
				dart run drift_dev make-migrations

dmg:
		flutter build macos &&\
		if [ -f dist/OpenMusic-macos-universal.dmg ];\
		then rm dist/OpenMusic-macos-universal.dmg;\
		fi &&\
		appdmg appdmg.json dist/OpenMusic-macos-universal.dmg

changelog:
	git-cliff --unreleased