import type { IconType } from "react-icons";
import {
  FaAndroid,
  FaApple,
  FaDebian,
  FaFedora,
  FaOpensuse,
  FaUbuntu,
  FaWindows,
  FaRedhat,
  FaLinux,
} from "react-icons/fa6";
import { LuHouse, LuNewspaper, LuDownload, LuBook } from "react-icons/lu";

export const routes: Record<string, [string, IconType | null]> = {
  "/": ["Home", LuHouse],
  "/blog": ["Blog", LuNewspaper],
  "/docs": ["Docs", LuBook],
  "/downloads": ["Downloads", LuDownload],
  "/about": ["About", null],
};

const releasesUrl =
  "https://github.com/MaybeItsAdam/openmusic/releases/latest/download";

export const downloadLinks: Record<string, [string, IconType[]]> = {
  "Android Apk": [`${releasesUrl}/OpenMusic-android-all-arch.apk`, [FaAndroid]],
  "Windows Executable": [
    `${releasesUrl}/OpenMusic-windows-x86_64-setup.exe`,
    [FaWindows],
  ],
  "macOS Dmg": [`${releasesUrl}/OpenMusic-macos-universal.dmg`, [FaApple]],
  "Ubuntu, Debian": [
    `${releasesUrl}/OpenMusic-linux-x86_64.deb`,
    [FaUbuntu, FaDebian],
  ],
  "Fedora, Redhat, Opensuse": [
    `${releasesUrl}/OpenMusic-linux-x86_64.rpm`,
    [FaFedora, FaRedhat, FaOpensuse],
  ],
  "iPhone Ipa": [`${releasesUrl}/OpenMusic-iOS.ipa`, [FaApple]],
};

export const extendedDownloadLinks: Record<
  string,
  [string, IconType[], string]
> = {
  Android: [`${releasesUrl}/OpenMusic-android-all-arch.apk`, [FaAndroid], "apk"],
  Windows: [
    `${releasesUrl}/OpenMusic-windows-x86_64-setup.exe`,
    [FaWindows],
    "exe",
  ],
  macOS: [`${releasesUrl}/OpenMusic-macos-universal.dmg`, [FaApple], "dmg"],
  "Ubuntu, Debian (x64)": [
    `${releasesUrl}/OpenMusic-linux-x86_64.deb`,
    [FaUbuntu, FaDebian],
    "deb",
  ],
  "Ubuntu, Debian (arm64)": [
    `${releasesUrl}/OpenMusic-linux-aarch64.deb`,
    [FaUbuntu, FaDebian],
    "deb",
  ],
  "Fedora, Redhat, Opensuse": [
    `${releasesUrl}/OpenMusic-linux-x86_64.rpm`,
    [FaFedora, FaRedhat, FaOpensuse],
    "rpm",
  ],
  "Linux AppImage (x64)": [
    `${releasesUrl}/OpenMusic-linux-x86_64.AppImage`,
    [FaLinux],
    "AppImage",
  ],
  "Linux AppImage (arm64)": [
    `${releasesUrl}/OpenMusic-linux-aarch64.AppImage`,
    [FaLinux],
    "AppImage",
  ],
  iPhone: [`${releasesUrl}/OpenMusic-iOS.ipa`, [FaApple], "ipa"],
};

const nightlyReleaseUrl =
  "https://github.com/MaybeItsAdam/openmusic/releases/download/nightly";

export const extendedNightlyDownloadLinks: Record<
  string,
  [string, IconType[], string]
> = {
  Android: [`${releasesUrl}/OpenMusic-android-all-arch.apk`, [FaAndroid], "apk"],
  Windows: [
    `${releasesUrl}/OpenMusic-windows-x86_64-setup.exe`,
    [FaWindows],
    "exe",
  ],
  macOS: [`${releasesUrl}/OpenMusic-macos-universal.dmg`, [FaApple], "dmg"],
  "Ubuntu, Debian (x64)": [
    `${releasesUrl}/OpenMusic-linux-x86_64.deb`,
    [FaUbuntu, FaDebian],
    "deb",
  ],
  "Ubuntu, Debian (arm64)": [
    `${releasesUrl}/OpenMusic-linux-aarch64.deb`,
    [FaUbuntu, FaDebian],
    "deb",
  ],
  "Fedora, Redhat, Opensuse": [
    `${releasesUrl}/OpenMusic-linux-x86_64.rpm`,
    [FaFedora, FaRedhat, FaOpensuse],
    "rpm",
  ],
  "Linux AppImage (x64)": [
    `${releasesUrl}/OpenMusic-linux-x86_64.AppImage`,
    [FaLinux],
    "AppImage",
  ],
  "Linux AppImage (arm64)": [
    `${releasesUrl}/OpenMusic-linux-aarch64.AppImage`,
    [FaLinux],
    "AppImage",
  ],
  iPhone: [`${releasesUrl}/OpenMusic-iOS.ipa`, [FaApple], "ipa"],
};

export const ADS_SLOTS = Object.freeze({
  rootPageDisplay: 5979549631,
  blogPageInFeed: 3386010031,
  downloadPageDisplay: 9928443050,
  packagePageArticle: 9119323068,
  // This is being used for rehype-auto-ads in svelte.config.js
  blogArticlePageArticle: 6788673194,
});
