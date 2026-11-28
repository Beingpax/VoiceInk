tell application id "at.studio.AsideBrowser"
    tell active tab of (first window whose visible is true)
        return URL
    end tell
end tell
