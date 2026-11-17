# File server import

The user can connect one file server in Settings, by FTPS or SFTP; with one connected, Songs imports its audio files.

## Choices

- **Encrypted or not at all.** There is no plain-FTP mode: FTPS (explicit `AUTH TLS` on the usual port 21, or implicit
  TLS on 990) and SFTP (SSH, port 22). A server that offers no TLS is refused, never used in the clear, so a password
  never travels readable.
- **FTPS is a client of our own** (`Packages/RehearsalFTP`). iOS has no FTP client left (URLSession dropped it).
  It speaks login, `PBSZ 0` and `PROT P` (the listings and the files are encrypted too), passive transfers (`EPSV`,
  then `PASV`), `MLSD` for listings with `LIST` as the fallback (Unix and DOS styles), `RETR` for files, and one way
  to write: `STOR` and `APPE`, used only for the missing-songs list. No delete, no rename.
- **TLS runs on SecureTransport over BSD sockets**, not Network.framework: `AUTH TLS` upgrades a connection that is
  already open, which Network.framework cannot do, and servers such as FileZilla Server and ProFTPD require a data
  connection to resume the control connection's TLS session, which only SecureTransport's peer id allows. Apple
  deprecated it (it builds with warnings, and speaks TLS 1.2 at most), so the hazard is a server that asks for 1.3
  only, or a future OS that drops the API. It is isolated in `SecureSocket.swift`, the one file to replace.
- **The certificate is checked** against the system's trust and the host name. A self-signed one is refused with a
  message that names the switch "Accept an untrusted certificate", which keeps the encryption and skips only the
  identity check. It is off by default and kept per server.
- **SFTP uses Citadel** (`Packages/RehearsalSFTP`, MIT, on Apple's SwiftNIO SSH), the one third-party library beyond
  GRDB and Yams, because Apple ships no SSH client. A password is the login; keys are not offered yet.
- **An SFTP host key is pinned at the first login** (trust on first use) and shown in Settings; a login that meets
  another key is refused, since that is what a man in the middle looks like. Disconnect forgets the key.
- **A passive FTPS data connection goes to the control connection's host**, never to the address the server
  announces, so a server behind a NAT that announces its private address still works.
- **One login per action** (a listing, a file). No session outlives a screen, so there is nothing to keep alive
  or to reconnect.
- **Only a login that worked is kept**: the protocol, host, port, user, folder, certificate switch and host key in
  UserDefaults, the password in the Keychain. Disconnect forgets all of it. A login of the removed plain-FTP mode is
  cleared at launch.
- **Files are downloaded first, then imported together** through the same path as a picked file, each in its own
  temp folder so two songs of the same name never meet; the temp folder goes after the import. A failed
  download imports nothing.
- **A missing song is one line in `MISSING-SONGS.md` at the root of the server**, whatever folder the import opens on:
  "- Artist - Title", blanks collapsed so a line break cannot split it. The line is added at the end of the file, so
  another writer's lines are never overwritten; the file is created with a title when it is not there, and a file that
  does not end with a line break gets one first. Both an artist and a title are required.
- **A stalled connection is cut after 20 seconds without a byte**; the pending call then throws.
- **Local Network permission**: a server on the LAN triggers iOS's prompt, with the text in `Info.plist`.

## Only a device can verify

- The Local Network prompt and a real server on the LAN. The FTPS tests use an in-process TLS server on the loopback,
  and the client was also run once against pyftpdlib (explicit TLS); no NAS, no implicit-TLS server, no server that
  requires session reuse was tried.
- A server that announces a private address, one without `EPSV`, one that lists in an unusual style.
- A large file over Wi-Fi, and what a call or a lock does to a running download.
- SFTP against a server with a password login (the checks used a key login on a local `sshd`).
