{...}: {
  stylix.targets.nixcord.enable = true;

  programs.nixcord = {
    enable = true;
    discord.enable = false;
    vesktop.enable = true;

    config = {
      frameless = true;

      plugins = {
        alwaysAnimate.enable = true;
        alwaysExpandRoles.enable = true;
        anonymiseFileNames.enable = true;
        betterFolders.enable = true;
        betterGifPicker.enable = true;
        betterSessions.enable = true;
        betterSettings.enable = true;
        betterUploadButton.enable = true;
        biggerStreamPreview.enable = true;
        callTimer.enable = true;
        clearURLs.enable = true;
        copyEmojiMarkdown.enable = true;
        copyFileContents.enable = true;
        disableCallIdle.enable = true;
        dontRoundMyTimestamps.enable = true;
        fakeNitro.enable = true;
        favoriteGifSearch.enable = true;
        fixCodeblockGap.enable = true;
        fixImagesQuality.enable = true;
        fixSpotifyEmbeds.enable = true;
        fixYoutubeEmbeds.enable = true;
        forceOwnerCrown.enable = true;
        friendsSince.enable = true;
        fullSearchContext.enable = true;
        gameActivityToggle.enable = true;
        gifPaste.enable = true;
        imageZoom.enable = true;
        ircColors.enable = true;
        loadingQuotes.enable = true;
        memberCount.enable = true;
        messageClickActions.enable = true;
        messageLinkEmbeds.enable = true;
        messageLogger.enable = true;
        noF1.enable = true;
        pictureInPicture.enable = true;
        pinDMs.enable = true;
        platformIndicators.enable = true;
        previewMessage.enable = true;
        quickReply.enable = true;
        readAllNotificationsButton.enable = true;
        replyTimestamp.enable = true;
        revealAllSpoilers.enable = true;
        reverseImageSearch.enable = true;
        roleColorEverywhere.enable = true;
        sendTimestamps.enable = true;
        serverInfo.enable = true;
        showHiddenChannels.enable = true;
        showTimeoutDuration.enable = true;
        silentMessageToggle.enable = true;
        spotifyCrack.enable = true;
        startupTimings.enable = true;
        typingIndicator.enable = true;
        typingTweaks.enable = true;
        unindent.enable = true;
        unlockedAvatarZoom.enable = true;
        userVoiceShow.enable = true;
        validReply.enable = true;
        validUser.enable = true;
        vcNarrator.enable = false;
        viewIcons.enable = true;
        volumeBooster.enable = true;
        webScreenShareFixes.enable = true;
        whoReacted.enable = true;
        youtubeAdblock.enable = true;

        betterNotesBox = {
          enable = true;
          noSpellCheck = true;
        };

        replaceGoogleSearch = {
          enable = true;
          customEngineName = "DuckDuckGo";
          customEngineURL = "https://duckduckgo.com";
        };

        showMeYourName = {
          enable = true;
          mode = "nick-user";
        };

        shikiCodeblocks = {
          enable = true;
          useDevIcon = "COLOR";
        };
      };
    };
  };

  home.file = {
    ".config/electron-flags.conf".source = ./electron-flags.conf;
  };
}
