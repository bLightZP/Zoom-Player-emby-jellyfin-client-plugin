The Delphi helper functions used by Zoom Player to communicate with Emby and Jellyfin media servers.

The following functions are supported:

**MediaServerAuthenticate**    
Authentication with the Server.

**MediaServerGetAvailableCategoryIDs**    
Lists top-level media library folders/collections/categories.

**MediaServerGetMediaFromParentID**    
Lists the content of media folders and sub-folders.

**MediaServerGetMediaStreamInfo**    
Constructing a playable stream URL derived from an ItemID extracted from previously listed media.

**Caching**    
For faster operations, network data is optionally cached for a specified number of days.
