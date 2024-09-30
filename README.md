# Introduction
I wrote helper functions for Zoom Player to communicate with Plex, Emby and Jellyfin media servers using an abstraction layer to make access as easy as possible.

The following functions are supported:

### MediaServerAuthenticate
Authentication with the Server.

### MediaServerGetAvailableCategoryIDs
Lists top-level media library folders/collections/categories.

### MediaServerGetMediaFromParentID
Lists the content of media folders and sub-folders.

### MediaServerGetMediaStreamInfo
Constructing a playable stream URL derived from an ItemID extracted from previously listed media.

# Caching
For faster operations, network data is optionally cached for a specified number of days.
