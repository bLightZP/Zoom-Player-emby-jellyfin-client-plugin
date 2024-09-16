{$I ZZZP_PRO.INC}
unit embyclientunit;

interface

uses classes;


function  EmbyAuthenticate(const ServerURL, Username, Password: string; out sToken, sID : string): Boolean;
procedure EmbyGetAvailableCoollectionIDs(const ServerURL, UserId, AccessToken: string; itemList : TList);
procedure EmbyGetMediaFromParentID(const ServerURL, UserId, ParentID, AccessToken : String; itemList : TList);
procedure EmbyGetMediaStreamInfo(const ServerURL, UserId, MediaID, AccessToken : String; itemList : TList);


type
  TEMBYCollectionRecord =
  Record
    crID              : WideString; // Collection ID
    crName            : WideString; // Title
    crIsFolder        : Boolean;    // It's a folder
    crType            : WideString; // e.g. "CollectionFolder"
    crCollectionType  : WideString; // e.g. "movies", "tvshows"
  End;
  PEMBYCollectionRecord = ^TEMBYCollectionRecord;

  TEMBYMediaRecord =
  Record
    mrID              : WideString; // Media ID
    mrName            : WideString; // Title
    mrRunTimeTicks    : Int64;      // Duration in "Ticks"
    mrIsFolder        : Boolean;
    mrType            : WideString; // e.g. "Series", "Folder"
    mrImagePrimaryID  : WideString;
    mrImageBackdropID : WideString;
  End;
  PEMBYMediaRecord = ^TEMBYMediaRecord;




implementation


uses
  Windows, SysUtils, Dialogs, WinInet, tntsysutils, ZPVars, General_Txt, Debugunit, superobject, mainunit, general_func;


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


function EmbyAuthenticate(const ServerURL, Username, Password: string; out sToken, sID : string): Boolean;
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
  AuthHeader         : String;
  PostData           : String;
  ServerName         : String;
  URLPath            : String;
  PortStr            : String;
  SchemeFlags        : DWORD;
  Port               : DWORD;
  Index              : DWORD;
  ErrorCode          : DWORD;
  ErrorMessage       : string;
  URLParts           : TURLComponents;

begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyAuthenticate (before)');{$ENDIF}
  Result  := False;
  sToken  := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
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
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    // Ensure URLPath ends with '/emby/Users/AuthenticateByName'
    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    URLPath := URLPath + 'emby/Users/AuthenticateByName';

    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Connecting to: ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

    hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    If hConn = nil then
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    Try
      hReq := HttpOpenRequest(hConn, 'POST', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
      If hReq = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        // Prepare POST data
        PostData := Format('{"Username":"%s","Pw":"%s"}', [URLEncodeUTF8(Username), URLEncodeUTF8(Password)]);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','POST data: '+CRLF+PostData+CRLF);{$ENDIF}

        // Prepare headers
        AuthHeader     := 'MediaBrowser Client="'+AppBase+'", Device="PC", DeviceId="WindowsPC", Version="'+GetZPVersionBase+'"';
        RequestHeaders := 'Content-Type: application/json'#13#10 +
                          'X-Emby-Authorization: '+AuthHeader;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

        // Send request
        If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), PChar(PostData), Length(PostData)) then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Check HTTP status code
        StatusCodeSize := SizeOf(StatusCode);
        Index := 0;
        If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
          If StatusCode <> 200 then
          Begin
            // Read and output error response
            ResponseText := '';
            Repeat
              FillChar(Buffer, SizeOf(Buffer), 0);
              InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
              ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
            Until BytesRead = 0;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server error response: ' + ResponseText);{$ENDIF}
            Exit;
          End;
        End
          else
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Read response
        ResponseText := '';
        Repeat
          FillChar(Buffer, SizeOf(Buffer), 0);
          InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
          ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
        Until BytesRead = 0;

        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

        // Extract token from response (simplified, you may need to use a JSON parser for robust parsing)
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
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Authentication successful. Token: ' + sToken);{$ENDIF}
          End
            else
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','JSON = NIL');{$ENDIF}
          End;
        End
          else
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Authentication failed. No token found in response.');{$ENDIF}
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
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyAuthenticate (after)'+CRLF);{$ENDIF}
end;


procedure EmbyGetAvailableCoollectionIDs(const ServerURL, UserId, AccessToken: string; itemList : TList);
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
  nEntry             : PEMBYCollectionRecord;

begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyGetAvailableItemIDs (before)');{$ENDIF}
  ResponseText := '';

  DebugMSGFT('c:\log\.Emby.txt','Server URL    : '+ServerURL);
  DebugMSGFT('c:\log\.Emby.txt','User ID       : '+UserID);
  DebugMSGFT('c:\log\.Emby.txt','Auth Token    : '+AccessToken);

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
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
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    // Ensure URLPath ends with '/emby/Users/AuthenticateByName'
    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *************************
    // *    URL Entry Point    *
    // *************************
    URLPath := URLPath + 'emby/Users/'+UserID+'/Items';
    //URLPath := URLPath + 'emby/Items';

    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Connecting to : ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

    hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    If hConn = nil then
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    Try
      hReq := HttpOpenRequest(hConn, 'GET', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
      If hReq = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        // Prepare headers
        RequestHeaders := 'Content-Type: application/json'#13#10 +
                          'X-Emby-Token: '+AccessToken;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

        // Send request
        If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), nil, 0) then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Check HTTP status code
        StatusCodeSize := SizeOf(StatusCode);
        Index := 0;
        If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
          If StatusCode <> 200 then
          Begin
            // Read and output error response
            Repeat
              FillChar(Buffer, SizeOf(Buffer), 0);
              InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
              ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
            Until BytesRead = 0;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server error response: '+CRLF+ResponseText+CRLF);{$ENDIF}
            Exit;
          End;
        End
          else
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Read response
        Repeat
          FillChar(Buffer, SizeOf(Buffer), 0);
          InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
          ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
        Until BytesRead = 0;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

        If ResponseText <> '' then
        Begin
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

                  {$IFDEF TRACEDEBUG}
                  DebugMSGFT('c:\log\.Emby.txt','ID              : '+nEntry^.crID);
                  DebugMSGFT('c:\log\.Emby.txt','Name            : '+nEntry^.crName);
                  DebugMSGFT('c:\log\.Emby.txt','Type            : '+nEntry^.crType);
                  DebugMSGFT('c:\log\.Emby.txt','Collection Type : '+nEntry^.crCollectionType);
                  DebugMSGFT('c:\log\.Emby.txt','IsFolder        : '+BoolToStr(nEntry^.crIsFolder,True));
                  DebugMSGFT('c:\log\.Emby.txt','-----------------');
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
              {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','idCount = 0');{$ENDIF}
            End;
          End
            else
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','JSON = NIL');{$ENDIF}
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
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyGetAvailableItemIDs (after)'+CRLF);{$ENDIF}
end;


procedure EmbyGetMediaFromParentID(const ServerURL, UserId, ParentID, AccessToken : String; itemList : TList);
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
  nEntry             : PEMBYMediaRecord;

begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyGetMediaFromParentID (before)');{$ENDIF}
  {$IFDEF TRACEDEBUG}
  DebugMSGFT('c:\log\.Emby.txt','Server URL    : '+ServerURL);
  DebugMSGFT('c:\log\.Emby.txt','User ID       : '+UserID);
  DebugMSGFT('c:\log\.Emby.txt','Parent ID     : '+ParentID);
  DebugMSGFT('c:\log\.Emby.txt','Auth Token    : '+AccessToken);
  {$ENDIF}
  ResponseText := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
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
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *************************
    // *    URL Entry Point    *
    // *************************
    URLPath := URLPath + 'emby/Users/'+UserID+'/Items?ParentId='+ParentID;

    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Connecting to : ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

    hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    If hConn = nil then
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    Try
      hReq := HttpOpenRequest(hConn, 'GET', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
      If hReq = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        // Prepare headers
        RequestHeaders := 'Content-Type: application/json'#13#10 +
                          'X-Emby-Token: '+AccessToken;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

        // Send request
        If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), nil, 0) then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Check HTTP status code
        StatusCodeSize := SizeOf(StatusCode);
        Index := 0;
        If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
          If StatusCode <> 200 then
          Begin
            // Read and output error response
            Repeat
              FillChar(Buffer, SizeOf(Buffer), 0);
              InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
              ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
            Until BytesRead = 0;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server error response: '+CRLF+ResponseText+CRLF);{$ENDIF}
            Exit;
          End;
        End
          else
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Read response
        Repeat
          FillChar(Buffer, SizeOf(Buffer), 0);
          InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
          ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
        Until BytesRead = 0;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

        If ResponseText <> '' then
        Begin
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


                  {$IFDEF TRACEDEBUG}
                  DebugMSGFT('c:\log\.Emby.txt','ID              : '+nEntry^.mrID);
                  DebugMSGFT('c:\log\.Emby.txt','Name            : '+nEntry^.mrName);
                  DebugMSGFT('c:\log\.Emby.txt','RunTimeTicks    : '+IntToStr(nEntry^.mrRunTimeTicks));
                  DebugMSGFT('c:\log\.Emby.txt','Type            : '+nEntry^.mrType);
                  DebugMSGFT('c:\log\.Emby.txt','ImagePrimaryID  : '+nEntry^.mrImagePrimaryID);
                  DebugMSGFT('c:\log\.Emby.txt','ImageBackdropID : '+nEntry^.mrImageBackdropID);
                  DebugMSGFT('c:\log\.Emby.txt','IsFolder        : '+BoolToStr(nEntry^.mrIsFolder,True));
                  DebugMSGFT('c:\log\.Emby.txt','-----------------');
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
              {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','idCount = 0');{$ENDIF}
            End;
          End
            else
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','JSON = NIL');{$ENDIF}
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
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyGetMediaFromParentID (after)'+CRLF);{$ENDIF}
end;


procedure EmbyGetMediaStreamInfo(const ServerURL, UserId, MediaID, AccessToken : String; itemList : TList);
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
  nEntry             : PEMBYMediaRecord;
begin
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyGetMediaStreamInfo (before)');{$ENDIF}
  {$IFDEF TRACEDEBUG}
  DebugMSGFT('c:\log\.Emby.txt','Server URL    : '+ServerURL);
  DebugMSGFT('c:\log\.Emby.txt','User ID       : '+UserID);
  DebugMSGFT('c:\log\.Emby.txt','Media ID      : '+MediaID);
  DebugMSGFT('c:\log\.Emby.txt','Auth Token    : '+AccessToken);
  {$ENDIF}
  ResponseText := '';

  hInet := InternetOpen(PChar(AppName), INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  If hInet = nil then
  begin
    ErrorCode := GetLastError;
    ErrorMessage := GetWinInetError(ErrorCode);
    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetOpen failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
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
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetCrackUrl failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    If (URLPath = '') or (URLPath[Length(URLPath)] <> '/') then
      URLPath := URLPath + '/';

    // *************************
    // *    URL Entry Point    *
    // *************************
    //URLPath := URLPath + 'emby/Items/'+MediaID+'/File';
    URLPath := URLPath + 'emby/Items/'+MediaID+'/PlaybackInfo?UserId='+UserID;
    //URLPath := URLPath + 'emby/Videos/'+MediaID+'/stream';

    {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Connecting to : ' + ServerName + ':' + IntToStr(Port) + URLPath);{$ENDIF}

    hConn := InternetConnect(hInet, PChar(ServerName), Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
    If hConn = nil then
    Begin
      ErrorCode := GetLastError;
      ErrorMessage := GetWinInetError(ErrorCode);
      {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','InternetConnect failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
      Exit;
    End;

    Try
      hReq := HttpOpenRequest(hConn, 'GET', PChar(URLPath), nil, nil, nil, SchemeFlags, 0);
      If hReq = nil then
      Begin
        ErrorCode := GetLastError;
        ErrorMessage := GetWinInetError(ErrorCode);
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpOpenRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
        Exit;
      End;

      Try
        // Prepare headers
        RequestHeaders := 'Content-Type: application/json'#13#10 +
                          'X-Emby-Token: '+AccessToken;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Request headers: '+CRLF+RequestHeaders+CRLF);{$ENDIF}

        // Send request
        If not HttpSendRequest(hReq, PChar(RequestHeaders), Length(RequestHeaders), nil, 0) then
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpSendRequest failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Check HTTP status code
        StatusCodeSize := SizeOf(StatusCode);
        Index := 0;
        If HttpQueryInfo(hReq, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @StatusCode, StatusCodeSize, Index) then
        Begin
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HTTP Status Code: ' + IntToStr(StatusCode));{$ENDIF}
          If StatusCode <> 200 then
          Begin
            // Read and output error response
            Repeat
              FillChar(Buffer, SizeOf(Buffer), 0);
              InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
              ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
            Until BytesRead = 0;
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server error response: '+CRLF+ResponseText+CRLF);{$ENDIF}
            Exit;
          End;
        End
          else
        Begin
          ErrorCode := GetLastError;
          ErrorMessage := GetWinInetError(ErrorCode);
          {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','HttpQueryInfo failed. Error: ' + IntToStr(ErrorCode) + ' - ' + ErrorMessage);{$ENDIF}
          Exit;
        End;

        // Read response
        Repeat
          FillChar(Buffer, SizeOf(Buffer), 0);
          InternetReadFile(hReq, @Buffer, SizeOf(Buffer), BytesRead);
          ResponseText := ResponseText + Copy(Buffer, 1, BytesRead);
        Until BytesRead = 0;
        {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','Server response: '+CRLF+ResponseText+CRLF);{$ENDIF}

        If ResponseText <> '' then
        Begin
          // http://{server_address}/Videos/{ItemId}/stream.{Container}?static=true&MediaSourceId={MediaSourceId}


          (*oJSON := SO(ResponseText);
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


                  {$IFDEF TRACEDEBUG}
                  DebugMSGFT('c:\log\.Emby.txt','ID              : '+nEntry^.mrID);
                  DebugMSGFT('c:\log\.Emby.txt','Name            : '+nEntry^.mrName);
                  DebugMSGFT('c:\log\.Emby.txt','RunTimeTicks    : '+IntToStr(nEntry^.mrRunTimeTicks));
                  DebugMSGFT('c:\log\.Emby.txt','Type            : '+nEntry^.mrType);
                  DebugMSGFT('c:\log\.Emby.txt','ImagePrimaryID  : '+nEntry^.mrImagePrimaryID);
                  DebugMSGFT('c:\log\.Emby.txt','ImageBackdropID : '+nEntry^.mrImageBackdropID);
                  DebugMSGFT('c:\log\.Emby.txt','IsFolder        : '+BoolToStr(nEntry^.mrIsFolder,True));
                  DebugMSGFT('c:\log\.Emby.txt','-----------------');
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
              {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','idCount = 0');{$ENDIF}
            End;
          End
            else
          Begin
            {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','JSON = NIL');{$ENDIF}
          End;*)
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
  {$IFDEF TRACEDEBUG}DebugMSGFT('c:\log\.Emby.txt','EmbyGetMediaStreamInfo (after)'+CRLF);{$ENDIF}
end;




end.
