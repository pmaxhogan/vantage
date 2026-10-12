import json

VANTAGE_URL = "https://github.com/pmaxhogan/vantage"
MICROG_URL  = "https://github.com/MorpheApp/MicroG-RE"

def app(app_id, name, author, url, addl):
    # additionalSettings is stored as a JSON-encoded string (Obtainium schema).
    return {
        "id": app_id,
        "url": url,
        "author": author,
        "name": name,
        "installedVersion": None,
        "latestVersion": None,
        "apkUrls": "[]",
        "otherAssetUrls": "[]",
        "preferredApkIndex": 0,
        "additionalSettings": json.dumps(addl),
        "lastUpdateCheck": None,
        "pinned": False,
        "categories": [],
        "releaseDate": None,
        "changeLog": None,
        "overrideSource": None,
        "allowIdChange": True,
        "pendingRepoRenameUrl": None,
    }

# Vantage GitHub-source settings: date-tagged multi-APK release -> key updates off
# the release DATE (releaseDateAsVersion), arch filter OFF, one APK via regex.
def vantage_addl(regex):
    return {
        "includePrereleases": False,
        "fallbackToOlderReleases": True,
        "filterReleaseTitlesByRegEx": "",
        "filterReleaseNotesByRegEx": "",
        "verifyLatestTag": False,
        "sortMethodChoice": "date",
        "useLatestAssetDateAsReleaseDate": False,
        "trackOnly": False,
        "versionExtractionRegEx": "",
        "matchGroupToUse": "",
        "versionDetection": False,
        "releaseDateAsVersion": True,
        "useVersionCodeAsOSVersion": False,
        "apkFilterRegEx": regex,
        "invertAPKFilter": False,
        "autoApkFilterByArch": False,
        "appName": "",
        "appAuthor": "",
    }

# MicroG-RE: normal semver releases -> standard versionName detection, arch
# filter OFF, one APK via regex. The regex is anchored to the universal APK
# (microg-<ver>.apk): the release also carries per-ABI splits, and the 32-bit one
# breaks stream fetching on a 64-bit phone.
microg_addl = {
    "includePrereleases": False,
    "fallbackToOlderReleases": True,
    "filterReleaseTitlesByRegEx": "",
    "filterReleaseNotesByRegEx": "",
    "verifyLatestTag": False,
    "sortMethodChoice": "date",
    "useLatestAssetDateAsReleaseDate": False,
    "trackOnly": False,
    "versionExtractionRegEx": "",
    "matchGroupToUse": "",
    "versionDetection": True,
    "releaseDateAsVersion": False,
    "useVersionCodeAsOSVersion": False,
    "apkFilterRegEx": r"^microg-[0-9][0-9.]*(-dev\.[0-9]+)?\.apk$",
    "invertAPKFilter": False,
    "autoApkFilterByArch": False,
    "appName": "",
    "appAuthor": "",
}

apps = [
    app("app.vantage.youtube", "Vantage", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"vantage-youtube-.*-anddea\.apk")),
    app("app.vantage.youtube.alt", "Vantage Alt", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"vantage-youtube-.*-alt\.apk")),
    app("app.vantage.youtube.music", "Vantage Music", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"vantage-music-.*\.apk")),
    # Vantage X ships on its own "x-v..." release cadence in the same repo, so the
    # newest release often has no vantage-x APK; fallbackToOlderReleases (on in
    # vantage_addl) walks back to the last X one.
    app("com.twitter.android", "Vantage X", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"vantage-x-.*-max2h\.apk")),
    # Postbox (patched Instagram) also ships on its own "postbox-v..." release
    # cadence, so the same fallbackToOlderReleases walk-back applies. The Obtainium
    # app id is the clone's package, not com.instagram.android.
    app("app.vantage.postbox", "Postbox", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"postbox-.*\.apk")),
    app("app.revanced.android.gms", "MicroG-RE", "MorpheApp", MICROG_URL,
        microg_addl),
    # Claude clones: several accounts signed in at once. Each is a renamed,
    # recolored copy of Claude with its own package id, so they install side by
    # side with the original app and with each other. They ship on their own
    # "claude-v..." release cadence in the same repo (like Vantage X), so
    # fallbackToOlderReleases walks back to the last claude-v release. The
    # Obtainium app id is the clone's real package - not the original app's -
    # since that's what has to match what's actually installed on the device.
    app("com.anthropic.claude.two", "Claude 2", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"claude-2-.*\.apk")),
    app("com.anthropic.claude.three", "Claude 3", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"claude-3-.*\.apk")),
    app("com.anthropic.claude.four", "Claude 4", "pmaxhogan", VANTAGE_URL,
        vantage_addl(r"claude-4-.*\.apk")),
]

config = {"apps": apps}
with open("obtainium-config.json", "w", encoding="utf-8", newline="\n") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("wrote obtainium-config.json with", len(apps), "apps")
