{ pkgs, ... }:

{
  home.packages = [ pkgs.davmail ];

  home.file.".davmail.properties".text = ''
    davmail.url=https://outlook.office365.com/EWS/Exchange.asmx
    davmail.mode=O365Interactive
    davmail.caldavPort=1080
    davmail.imapPort=1143
    davmail.ldapPort=1389
    davmail.popPort=1110
    davmail.smtpPort=1025
    davmail.server=true
    davmail.allowRemote=false
    davmail.bindAddress=127.0.0.1
    davmail.ssl.nosecurecaldav=false
  '';

  systemd.user.services.davmail = {
    Unit = {
      Description = "DavMail Gateway";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.davmail}/bin/davmail %h/.davmail.properties";
      Restart = "on-failure";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
