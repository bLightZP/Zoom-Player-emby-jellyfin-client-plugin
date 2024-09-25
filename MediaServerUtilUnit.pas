{$I ZZZP_PRO.INC}
{$DEFINE CONTENTTRACE}
{$DEFINE HEADERSTRACE}

unit MediaServerUtilUnit;

interface

uses classes;


function  MediaServerAuthenticate(const ServerURL : String; const ServerType : Integer; const Username, Password: string; out sToken, sID : string): Boolean;
procedure MediaServerGetAvailableCollectionIDs(const ServerURL : String; const ServerType : Integer; const UserId, AccessToken: string; itemList : TList; IgnoreCache : Boolean);
procedure MediaServerGetMediaFromParentID(const ServerURL : String; const ServerType : Integer; const UserId, ParentID, AccessToken : String; itemList : TList; IgnoreCache : Boolean);
function  MediaServerGetMediaStreamInfo(const ServerURL : String; const ServerType : Integer; const UserId, ItemID, AccessToken : String) : String;

function  MediaServerURLLoadCache(sURL : String; CacheDuration : Integer) : String;
procedure MediaServerURLSaveCache(sURL : String; const sData : String);

const
  strMediaServer_JSON    : String = '.json';
  strMediaServer_JSONnew : String = '.newjson';

  mediaServerJellyfin    = 0;
  mediaServerEmby        = 1;
  mediaServerPlex        = 2;

  drTypeCollection       = 0;
  drTypeMedia            = 1;

type
  TMediaServerCollectionRecord =
  Record
    crID              : WideString; // Collection ID
    crName            : WideString; // Title
    crIsFolder        : Boolean;    // It's a folder
    crType            : WideString; // e.g. "CollectionFolder"
    crCollectionType  : WideString; // e.g. "movies", "tvshows"
  End;
  PMediaServerCollectionRecord = ^TMediaServerCollectionRecord;

  TMediaServerMediaRecord =
  Record
    mrID              : WideString; // Media ID
    mrName            : WideString; // Title
    mrRunTimeTicks    : Int64;      // Duration in "Ticks"
    mrIsFolder        : Boolean;
    mrType            : WideString; // e.g. "Series", "Folder"
    mrImagePrimaryID  : WideString;
    mrImageBackdropID : WideString;
  End;
  PMediaServerMediaRecord = ^TMediaServerMediaRecord;

  TMediaServerDisplayRecord =
  Record
    drType            : Integer; // Collection or Media
    drIndex           : Integer;
  End;
  PMediaServerDisplayRecord = ^TMediaServerDisplayRecord;

  TMediaServerBreadCrumbRecord =
  Record
    bcParentID        : WideString;
    bcParentName      : WideString;
  End;
  PMediaServerBreadCrumbRecord = ^TMediaServerBreadCrumbRecord;


var
  OPMediaServerType         : Integer    = mediaServerJellyfin;
  OPMediaServerUserName     : WideString = '';
  OPMediaServerPassword     : WideString = '';
  OPMediaServerURL          : WideString = '';
  OPMediaServerCacheDur     : Integer    = 7;
  OPMediaServerUserID       : String     = '';
  OPMediaServerToken        : String     = '';


implementation


uses
  Windows, SysUtils, Dialogs, WinInet, tntsysutils, tntclasses, ZPVars, General_Txt, Debugunit, superobject, mainunit, general_func, parseunit, md5;


// Helper function to get error message
function GetWinInetError(ErrorCode: DWORD): string;
var
  Buf: array[0..255] of Char;
begin
  FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_FROM_HMODULE,
                Pointer(GetModuleHandle('wininet.dll')), ErrorCode,
                0, @Buf[0], 256, nil);
  Result := Buf;
end;


function MediaServerURLLoadCache(sURL : String; CacheDuration : Integer) : String;
var
  fStream : TTNTFileStream;
  sList   : TStringList;
  sPath   : WideString;
begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerURLLoadCache "'+sURL+'", Duration "'+IntToStr(CacheDuration)+'" (before)');{$ENDIF}
  Result := '';
  sPath  := CFGPath+MediaCachePath+MediaCacheMSdb+StringMD5Digest(sURL)+strMediaServer_JSON;

  sList  := TStringList.Create;
  If WideFileExists(sPath) = True then
  Begin
    // Limit cache to [x] number of days
    If Now-FileDateToDateTime(FileAgeW(sPath)) < CacheDuration then
    Begin
      Try
        fStream := TTNTFileStream.Create(sPath,fmOpenRead or fmShareDenyNone);
      Except
        On E : Exception do
        Begin
          fStream := nil;
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Exception opening file "'+E.Message+'"');{$ENDIF}
        End;
      end;

      If fStream <> nil then
      Begin
        Try
          sList.LoadFromStream(fStream);
        Except
          On E : Exception do
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Exception reading file "'+E.Message+'"');{$ENDIF}
          End;
        End;
        Result := sList.Text;
        fStream.Free;
      End;
    End;
  End
    else
  Begin
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','File not found');{$ENDIF}
  End;
  sList.Free;
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerURLLoadCache (after)');{$ENDIF}
end;


procedure MediaServerURLSaveCache(sURL : String; const sData : String);
var
  fStream : TTNTFileStream;
  sList   : TStringList;
  bFail   : Boolean;
  sPath   : WideString;
begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerURLSaveCache "'+sURL+'" (before)');{$ENDIF}
  If WideDirectoryExists(CFGPath+MediaCachePath+MediaCacheMSdb) = False then
  Begin
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Creating folder "'+CFGPath+MediaCachePath+MediaCacheMSdb+'"');{$ENDIF}
    WideForceDirectories(CFGPath+MediaCachePath+MediaCacheMSdb);
  End;

  sPath  := CFGPath+MediaCachePath+MediaCacheMSdb+StringMD5Digest(sURL);

  Try
    fStream := TTNTFileStream.Create(sPath+strMediaServer_JSONnew,fmCreate);
  Except
    On E : Exception do
    Begin
      fStream := nil;
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Exception creating file "'+E.Message+'"');{$ENDIF}
    End;
  end;

  If fStream <> nil then
  Begin
    sList      := TStringList.Create;
    sList.Text := sData;
    bFail      := False;
    Try
      sList.SaveToStream(fStream);
    Except
      On E : Exception do
      Begin
        bFail := True;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Exception saving data "'+E.Message+'"');{$ENDIF}
      End;
    End;
    sList.Free;
    fStream.Free;

    If bFail = False then
    Begin
      EraseFile(sPath+strMediaServer_JSON);
      WideRenameFile(sPath+strMediaServer_JSONnew,sPath+strMediaServer_JSON);
    End;
  End;
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerURLSaveCache (after)');{$ENDIF}
end;


function MediaServerAuthenticate(const ServerURL : String; const ServerType : Integer; const Username, Password: string; out sToken, sID : string): Boolean;
var
  oJSON              : ISuperObject;
  hInet              : HINTERNET;
  hConn              : HINTERNET;
  hReq               : HINTERNET;
  Buffer             : Array[0..4095] of Char;
  BytesRead          : DWORD;
  StatusCode         : DWORD;
  StatusCodeSize     : DWORD;
  ResponseText       : String;
  RequestHeaders     : String;
  PostData           : String;
  ServerName         : String;
  URLPath            : String;
  PortStr            : String;
  SchemeFlags        : DWORD;
  Port               : DWORD;
  Index              : DWORD;
  ErrorCode          : DWORD;
  ErrorMessage       : String;
  URLParts           : TURLComponents;
  sHeaders           : String;

begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerAuthenticate (before)');{$ENDIF}
  Result  := False;
  sToken  := '';
  sID     := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
    Exit;
  end;

  Try
    // Parse ServerURL
    FillChar(URLParts, SizeOf(URLParts), 0);
    URLParts.dwStructSize     := SizeOf(URLParts);
    URLParts.dwSchemeLength   := 1;
    URLParts.dwHostNameLength := 1;
    URLParts.dwUrlPathLength  := 1;

    If InternetCrackUrl(PChar(ServerURL), Length(ServerURL), 0, URLParts) then
    Begin
      SetString(ServerName, URLParts.lpszHostName, URLParts.dwHostNameLength);
      SetString(URLPath, URLParts.lpszUrlPath, URLParts.dwUrlPathLength);
      Port := URLParts.nPort;

      If URLParts.nScheme = INTERNET_SCHEME_HTTPS then
        SchemeFlags := INTERNET_FLAG_SECURE else
        SchemeFlags := 0;
    End
      else
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *********************************************
    // *             Authenticate Path             *
    // *********************************************
    Case ServerType of
      mediaServerEmby :
      Begin
        URLPath  := URLPath + 'emby/Users/AuthenticateByName';
        sHeaders := 'X-Emby-Authorization: MediaBrowser Client="'+AppBase+'", Device="PC", DeviceId="WindowsPC", Version="'+GetZPVersionBase+'"';
      End;
      mediaServerJellyfin :
      Begin
        URLPath  := URLPath + 'Users/AuthenticateByName';
        sHeaders := 'Authorization: MediaBrowser Client="'+AppBase+'", Device="PC", DeviceId="WindowsPC", Version="'+GetZPVersionBase+'"';
      End;
      mediaServerPlex :
      Begin
      End;
    End;

    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Connecting to: ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

    hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    If hConn = nil then
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    Try
      hReq := HttpOpenRequest(hConn, 'POST', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
      If hReq = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        // Prepare POST data
        PostData := Format('{"Username":"%s","Pw":"%s"}', [URLEncodeUTF8(Username), URLEncodeUTF8(Password)]);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','POST data: '+CRLF+PostData+CRLF);{$ENDIF}

        // Prepare headers
        RequestHeaders := 'Content-Type: application/json'#13#10 + sHeaders;
        {$IFDEF HEADERSTRACE}DebugMSGFT('c:\log\.MediaServerUtil.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

        // Send request
        If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), PChar(PostData), Length(PostData)) then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Check HTTP status code
        StatusCodeSize := SizeOf(StatusCode);
        Index := 0;
        If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
          If StatusCode <> 200 then
          Begin
            // Read and output error response
            ResponseText := '';
            Repeat
              FillChar(Buffer, SizeOf(Buffer), 0);
              InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
              ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
            Until BytesRead = 0;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server error response: ' + ResponseText);{$ENDIF}
            Exit;
          End;
        End
          else
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Read response
        ResponseText := '';
        Repeat
          FillChar(Buffer, SizeOf(Buffer), 0);
          InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
          ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
        Until BytesRead = 0;

        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}


        // *********************************************
        // *           Authenticate Processing         *
        // *********************************************
        // Extract Token/UserID from response
        If Pos('"AccessToken":', ResponseText) > 0 then
        Begin
          oJSON := SO(ResponseText);

          If oJSON <> nil then
          Begin
            sToken := oJSON.S['AccessToken'];
            sID    := oJSON.S['User.Id'];

            oJSON.Clear(True);
            oJSON := nil;

            Result := True;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Authentication successful. Token: ' + sToken);{$ENDIF}
          End
            else
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','JSON = NIL');{$ENDIF}
          End;
        End
          else
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Authentication failed. No token found in response.');{$ENDIF}
        End;
      Finally
        InternetCloseHandle(hReq);
      End;
    Finally
      InternetCloseHandle(hConn);
    End;
  Finally
    InternetCloseHandle(hInet);
  End;
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerAuthenticate (after)'+CRLF);{$ENDIF}
end;


procedure MediaServerGetAvailableCollectionIDs(const ServerURL : String; const ServerType : Integer; const UserId, AccessToken: string; itemList : TList; IgnoreCache : Boolean);
var
  oJSON              : ISuperObject;
  oItems             : ISuperObject;
  hInet              : HINTERNET;
  hConn              : HINTERNET;
  hReq               : HINTERNET;
  Buffer             : Array[0..4095] of Char;
  BytesRead          : DWORD;
  StatusCode         : DWORD;
  StatusCodeSize     : DWORD;
  ResponseText       : String;
  RequestHeaders     : String;
  AuthHeader         : String;
  PostData           : String;
  ServerName         : String;
  URLPath            : String;
  PortStr            : String;
  SchemeFlags        : DWORD;
  Port               : DWORD;
  Index              : DWORD;
  ErrorCode          : DWORD;
  I                  : Integer;
  idCount            : Integer;
  ErrorMessage       : string;
  URLParts           : TURLComponents;
  nEntry             : PMediaServerCollectionRecord;
  sHeaders           : String;

begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerGetAvailableItemIDs (before)');{$ENDIF}
  {$IFDEF TRACEDEBUG}
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Server URL    : '+ServerURL);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','User ID       : '+UserID);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Auth Token    : '+AccessToken);
  {$ENDIF}

  ResponseText := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
    Exit;
  end;

  Try
    // Parse ServerURL
    FillChar(URLParts, SizeOf(URLParts), 0);
    URLParts.dwStructSize     := SizeOf(URLParts);
    URLParts.dwSchemeLength   := 1;
    URLParts.dwHostNameLength := 1;
    URLParts.dwUrlPathLength  := 1;

    If InternetCrackUrl(PChar(ServerURL), Length(ServerURL), 0, URLParts) then
    Begin
      SetString(ServerName, URLParts.lpszHostName, URLParts.dwHostNameLength);
      SetString(URLPath, URLParts.lpszUrlPath, URLParts.dwUrlPathLength);
      Port := URLParts.nPort;

      If URLParts.nScheme = INTERNET_SCHEME_HTTPS then
        SchemeFlags := INTERNET_FLAG_SECURE else
        SchemeFlags := 0;
    End
      else
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    // Ensure URLPath ends with '/emby/Users/AuthenticateByName'
    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *********************************************
    // *             Collections Path              *
    // *********************************************

    Case ServerType of
      mediaServerEmby :
      Begin
        URLPath  := URLPath + 'emby/Users/'+UserID+'/Items';
        sHeaders := 'X-Emby-Token: '+AccessToken;
      End;
      mediaServerJellyfin :
      Begin
        URLPath  := URLPath + 'UserViews?userId='+UserID;
        sHeaders := 'Authorization: MediaBrowser Token="'+AccessToken+'"'{+CRLF+
                    'userId: '+UserID+CRLF+
                    'includeExternalContent: false'};
      End;
      mediaServerPlex :
      Begin
      End;
    End;


    If IgnoreCache = False then
      ResponseText := MediaServerURLLoadCache(ServerURL+URLPath,OPMediaServerCacheDur);

    If ResponseText = '' then
    Begin
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Connecting to : ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

      hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
      If hConn = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        hReq := HttpOpenRequest(hConn, 'GET', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
        If hReq = nil then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        Try
          // Prepare headers
          RequestHeaders := 'Content-Type: application/json'+CRLF+sHeaders;
          {$IFDEF HEADERSTRACE}DebugMSGFT('c:\log\.MediaServerUtil.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

          // Send request
          If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), nil, 0) then
          Begin
            ErrorCode := GetLastError;
            ErrorMessage := GetWinInetError(ErrorCode);
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
            Exit;
          End;

          // Check HTTP status code
          StatusCodeSize := SizeOf(StatusCode);
          Index := 0;
          If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
            If StatusCode <> 200 then
            Begin
              // Read and output error response
              Repeat
                FillChar(Buffer, SizeOf(Buffer), 0);
                InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
                ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
              Until BytesRead = 0;
              {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server error response: '+CRLF+ResponseText+CRLF);{$ENDIF}
              Exit;
            End;
          End
            else
          Begin
            ErrorCode := GetLastError;
            ErrorMessage := GetWinInetError(ErrorCode);
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
            Exit;
          End;

          // Read response
          Repeat
            FillChar(Buffer, SizeOf(Buffer), 0);
            InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
            ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
          Until BytesRead = 0;
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

          If ResponseText <> '' then
            MediaServerURLSaveCache(ServerURL+URLPath,ResponseText);

        Finally
          InternetCloseHandle(hReq);
        End;
      Finally
        InternetCloseHandle(hConn);
      End;
    End
      else
    Begin
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Using Cache');{$ENDIF}
    End;
  Finally
    InternetCloseHandle(hInet);
  End;

  If ResponseText <> '' then
  Begin
    // *********************************************
    // *          Collections Processing           *
    // *********************************************
    oJSON := SO(ResponseText);
    If oJSON <> nil then
    Begin
      idCount := oJSON.I['TotalRecordCount'];
      If idCount > 0 then
      Begin
        oItems := oJson.O['Items'];

        If oItems <> nil then
        Begin
          For I := 0 to idCount-1 do
          Begin
            New(nEntry);

            nEntry^.crID             := oItems.AsArray.O[I].S['Id'];
            nEntry^.crName           := oItems.AsArray.O[I].S['Name'];
            nEntry^.crIsFolder       := oItems.AsArray.O[I].B['IsFolder'];
            nEntry^.crType           := oItems.AsArray.O[I].S['Type'];
            nEntry^.crCollectionType := oItems.AsArray.O[I].S['CollectionType'];

            {$IFDEF CONTENTTRACE}
            DebugMSGFT('c:\log\.MediaServerUtil.txt',CRLF+
              'ID              : '+nEntry^.crID+CRLF+
              'Name            : '+nEntry^.crName+CRLF+
              'Type            : '+nEntry^.crType+CRLF+
              'Collection Type : '+nEntry^.crCollectionType+CRLF+
              'IsFolder        : '+BoolToStr(nEntry^.crIsFolder,True)+CRLF+
            '-----------------');
            {$ENDIF}
            itemList.Add(nEntry);
          End;
          oItems.Clear(True);
          oItems := nil;
        End;
        oJSON.Clear(True);
        oJSON := nil;
      End
        else
      Begin
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','idCount = 0');{$ENDIF}
      End;
    End
      else
    Begin
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','JSON = NIL');{$ENDIF}
    End;
  End;

  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerGetAvailableItemIDs (after)'+CRLF);{$ENDIF}
end;


procedure MediaServerGetMediaFromParentID(const ServerURL : String; const ServerType : Integer; const UserId, ParentID, AccessToken : String; itemList : TList; IgnoreCache : Boolean);
var
  oJSON              : ISuperObject;
  oItems             : ISuperObject;
  hInet              : HINTERNET;
  hConn              : HINTERNET;
  hReq               : HINTERNET;
  Buffer             : Array[0..4095] of Char;
  BytesRead          : DWORD;
  StatusCode         : DWORD;
  StatusCodeSize     : DWORD;
  ResponseText       : String;
  RequestHeaders     : String;
  AuthHeader         : String;
  PostData           : String;
  ServerName         : String;
  URLPath            : String;
  PortStr            : String;
  SchemeFlags        : DWORD;
  Port               : DWORD;
  Index              : DWORD;
  ErrorCode          : DWORD;
  I                  : Integer;
  idCount            : Integer;
  ErrorMessage       : string;
  URLParts           : TURLComponents;
  nEntry             : PMediaServerMediaRecord;
  sHeaders           : String;

begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerGetMediaFromParentID (before)');{$ENDIF}
  {$IFDEF TRACEDEBUG}
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Server URL    : '+ServerURL);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','User ID       : '+UserID);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Parent ID     : '+ParentID);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Auth Token    : '+AccessToken);
  {$ENDIF}
  ResponseText := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
    Exit;
  end;

  Try
    // Parse ServerURL
    FillChar(URLParts, SizeOf(URLParts), 0);
    URLParts.dwStructSize     := SizeOf(URLParts);
    URLParts.dwSchemeLength   := 1;
    URLParts.dwHostNameLength := 1;
    URLParts.dwUrlPathLength  := 1;

    If InternetCrackUrl(PChar(ServerURL), Length(ServerURL), 0, URLParts) then
    Begin
      SetString(ServerName, URLParts.lpszHostName, URLParts.dwHostNameLength);
      SetString(URLPath, URLParts.lpszUrlPath, URLParts.dwUrlPathLength);
      Port := URLParts.nPort;

      If URLParts.nScheme = INTERNET_SCHEME_HTTPS then
        SchemeFlags := INTERNET_FLAG_SECURE else
        SchemeFlags := 0;
    End
      else
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *********************************************
    // *          Media From Parent Path           *
    // *********************************************

    Case ServerType of
      mediaServerEmby :
      Begin
        URLPath  := URLPath + 'emby/Users/'+UserID+'/Items?ParentId='+ParentID;
        sHeaders := 'X-Emby-Token: '+AccessToken;
      End;
      mediaServerJellyfin :
      Begin
        URLPath  := URLPath + 'Items?userId='+UserID+'&parentId='+ParentID;
        //URLPath  := URLPath + 'Items?parentId='+ParentID;
        sHeaders := 'Authorization: MediaBrowser Token="'+AccessToken+'"';
      End;
      mediaServerPlex :
      Begin
      End;
    End;

    If IgnoreCache = False then
      ResponseText := MediaServerURLLoadCache(ServerURL+URLPath,OPMediaServerCacheDur);

    If ResponseText = '' then
    Begin
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Connecting to : ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

      hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
      If hConn = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        hReq := HttpOpenRequest(hConn, 'GET', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
        If hReq = nil then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        Try
          // Prepare headers
          RequestHeaders := 'Content-Type: application/json'#13#10 + sHeaders;
          {$IFDEF HEADERSTRACE}DebugMSGFT('c:\log\.MediaServerUtil.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

          // Send request
          If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), nil, 0) then
          Begin
            ErrorCode := GetLastError;
            ErrorMessage := GetWinInetError(ErrorCode);
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
            Exit;
          End;

          // Check HTTP status code
          StatusCodeSize := SizeOf(StatusCode);
          Index := 0;
          If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
            If StatusCode <> 200 then
            Begin
              // Read and output error response
              Repeat
                FillChar(Buffer, SizeOf(Buffer), 0);
                InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
                ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
              Until BytesRead = 0;
              {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server error response: '+CRLF+ResponseText+CRLF);{$ENDIF}
              Exit;
            End;
          End
            else
          Begin
            ErrorCode := GetLastError;
            ErrorMessage := GetWinInetError(ErrorCode);
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
            Exit;
          End;

          // Read response
          Repeat
            FillChar(Buffer, SizeOf(Buffer), 0);
            InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
            ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
          Until BytesRead = 0;
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

          If ResponseText <> '' then
            MediaServerURLSaveCache(ServerURL+URLPath,ResponseText);

        Finally
          InternetCloseHandle(hReq);
        End;
      Finally
        InternetCloseHandle(hConn);
      End;
    End
      else
    Begin
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Using Cache');{$ENDIF}
    End;
  Finally
    InternetCloseHandle(hInet);
  End;

  If ResponseText <> '' then
  Begin
    // *********************************************
    // *       Media From Parent Processing        *
    // *********************************************
    oJSON := SO(ResponseText);
    If oJSON <> nil then
    Begin
      idCount := oJSON.I['TotalRecordCount'];
      If idCount > 0 then
      Begin
        oItems := oJson.O['Items'];

        If oItems <> nil then
        Begin
          For I := 0 to idCount-1 do
          Begin
            New(nEntry);

            nEntry^.mrID              := oItems.AsArray.O[I].S['Id'];
            nEntry^.mrName            := oItems.AsArray.O[I].S['Name'];
            nEntry^.mrRunTimeTicks    := oItems.AsArray.O[I].I['RunTimeTicks'];
            nEntry^.mrIsFolder        := oItems.AsArray.O[I].B['IsFolder'];
            nEntry^.mrType            := oItems.AsArray.O[I].S['Type'];
            nEntry^.mrImagePrimaryID  := oItems.AsArray.O[I].S['ImageTags.Primary'];

            If oItems.AsArray.O[I].A['BackdropImageTags'].Length > 0 then
              nEntry^.mrImageBackdropID := oItems.AsArray.O[I].A['BackdropImageTags'].S[0] else
              nEntry^.mrImageBackdropID := '';


            {$IFDEF CONTENTTRACE}
            DebugMSGFT('c:\log\.MediaServerUtil.txt',CRLF+
              'ID              : '+nEntry^.mrID+CRLF+
              'Name            : '+nEntry^.mrName+CRLF+
              'RunTimeTicks    : '+IntToStr(nEntry^.mrRunTimeTicks)+CRLF+
              'Type            : '+nEntry^.mrType+CRLF+
              'ImagePrimaryID  : '+nEntry^.mrImagePrimaryID+CRLF+
              'ImageBackdropID : '+nEntry^.mrImageBackdropID+CRLF+
              'IsFolder        : '+BoolToStr(nEntry^.mrIsFolder,True)+CRLF+
              '-----------------');
            {$ENDIF}

            itemList.Add(nEntry);
          End;
          oItems.Clear(True);
          oItems := nil;
        End;
        oJSON.Clear(True);
        oJSON := nil;
      End
        else
      Begin
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','idCount = 0');{$ENDIF}
      End;
    End
      else
    Begin
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','JSON = NIL');{$ENDIF}
    End;
  End;
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerGetMediaFromParentID (after)'+CRLF);{$ENDIF}
end;


function MediaServerGetMediaStreamInfo(const ServerURL : String; const ServerType : Integer; const UserId, ItemID, AccessToken : String) : String;
var
  oJSON              : ISuperObject;
  oMediaSources      : ISuperObject;
  hInet              : HINTERNET;
  hConn              : HINTERNET;
  hReq               : HINTERNET;
  Buffer             : Array[0..4095] of Char;
  BytesRead          : DWORD;
  StatusCode         : DWORD;
  StatusCodeSize     : DWORD;
  ResponseText       : String;
  RequestHeaders     : String;
  AuthHeader         : String;
  PostData           : String;
  ServerName         : String;
  URLPath            : String;
  PortStr            : String;
  SchemeFlags        : DWORD;
  Port               : DWORD;
  Index              : DWORD;
  ErrorCode          : DWORD;
  I                  : Integer;
  iCount             : Integer;
  ErrorMessage       : string;
  URLParts           : TURLComponents;
  MediaID            : WideString;
  MediaContainer     : WideString;
  sHeaders           : String;



begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerGetMediaStreamInfo (before)');{$ENDIF}
  {$IFDEF TRACEDEBUG}
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Server URL    : '+ServerURL);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','User ID       : '+UserID);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Media ID      : '+MediaID);
  DebugMSGFT('c:\log\.MediaServerUtil.txt','Auth Token    : '+AccessToken);
  {$ENDIF}

  Result       := '';
  ResponseText := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
    Exit;
  end;

  Try
    // Parse ServerURL
    FillChar(URLParts, SizeOf(URLParts), 0);
    URLParts.dwStructSize     := SizeOf(URLParts);
    URLParts.dwSchemeLength   := 1;
    URLParts.dwHostNameLength := 1;
    URLParts.dwUrlPathLength  := 1;

    If InternetCrackUrl(PChar(ServerURL), Length(ServerURL), 0, URLParts) then
    Begin
      SetString(ServerName, URLParts.lpszHostName, URLParts.dwHostNameLength);
      SetString(URLPath, URLParts.lpszUrlPath, URLParts.dwUrlPathLength);
      Port := URLParts.nPort;

      If URLParts.nScheme = INTERNET_SCHEME_HTTPS then
        SchemeFlags := INTERNET_FLAG_SECURE else
        SchemeFlags := 0;
    End
      else
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *********************************************
    // *              Media Info Path              *
    // *********************************************
    //URLPath := URLPath + 'emby/Items/'+MediaID+'/File';

    //URLPath := URLPath + 'emby/Videos/'+MediaID+'/stream';

    Case ServerType of
      mediaServerEmby :
      Begin
        URLPath := URLPath + 'emby/Items/'+ItemID+'/PlaybackInfo?UserId='+UserID;
        sHeaders := 'X-Emby-Token: '+AccessToken;
      End;
      mediaServerJellyfin :
      Begin
        URLPath := URLPath + 'Items/'+ItemID+'/PlaybackInfo?UserId='+UserID;
        sHeaders := 'Authorization: MediaBrowser Token="'+AccessToken+'"';
      End;
      mediaServerPlex :
      Begin
      End;
    End;


    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Connecting to : ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

    hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    If hConn = nil then
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    Try
      hReq := HttpOpenRequest(hConn, 'GET', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
      If hReq = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        // Prepare headers
        RequestHeaders := 'Content-Type: application/json'#13#10 + sHeaders;

        {$IFDEF HEADERSTRACE}DebugMSGFT('c:\log\.MediaServerUtil.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

        // Send request
        If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), nil, 0) then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Check HTTP status code
        StatusCodeSize := SizeOf(StatusCode);
        Index := 0;
        If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
          If StatusCode <> 200 then
          Begin
            // Read and output error response
            Repeat
              FillChar(Buffer, SizeOf(Buffer), 0);
              InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
              ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
            Until BytesRead = 0;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server error response: '+CRLF+ResponseText+CRLF);{$ENDIF}
            Exit;
          End;
        End
          else
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Read response
        Repeat
          FillChar(Buffer, SizeOf(Buffer), 0);
          InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
          ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
        Until BytesRead = 0;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

        If ResponseText <> '' then
        Begin
          // *********************************************
          // *           Media Info Processing           *
          // *********************************************
          // http://{server_address}/Videos/{ItemId}/stream.{Container}?static=true&MediaSourceId={MediaSourceId}

          oJSON := SO(ResponseText);
          If oJSON <> nil then
          Begin
            oMediaSources := oJSON.O['MediaSources'];

            If oMediaSources <> nil then
            Begin
              iCount := oMediaSources.AsArray.Length;
              If iCount > 0 then
              Begin
                // Using the first entry, not looking for any quality at the moment.
                MediaID        := oMediaSources.AsArray[0].S['Id'];
                MediaContainer := oMediaSources.AsArray[0].S['Container'];

                Result := AddFrontSlash(ServerURL)+'Videos/'+ItemID+'/stream.'+MediaContainer+'?static=true&MediaSourceId='+MediaID+'&X-Emby-Token='+AccessToken;

                {$IFDEF CONTENTTRACE}
                DebugMSGFT('c:\log\.MediaServerStream.txt',CRLF+
                  'Media Name      : '+oMediaSources.AsArray[0].S['Name']+CRLF+
                  'Media ID        : '+MediaID+CRLF+
                  'Stream          : '+Result+CRLF+
                  '-----------------');
                {$ENDIF}
              End;
              oMediaSources.Clear(True);
              oMediaSources := nil;
            End;

            oJSON.Clear(True);
            oJSON := nil;
          End
            else
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','JSON = NIL');{$ENDIF}
          End;
        End;
      Finally
        InternetCloseHandle(hReq);
      End;
    Finally
      InternetCloseHandle(hConn);
    End;
  Finally
    InternetCloseHandle(hInet);
  End;
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.MediaServerUtil.txt','MediaServerGetMediaStreamInfo (after)'+CRLF);{$ENDIF}
end;




end.
