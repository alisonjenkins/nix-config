{ pkgs
, username
, ...
}: {
  programs.k9s = {
    enable = true;
    package = pkgs.unstable.k9s;
    settings = {
      refreshRate = 2;
      maxConnRetry = 5;
      enableMouse = false;
      headless = false;
      logoless = false;
      crumbsless = false;
      readOnly = false;
      noExitOnCtrlC = false;
      noIcons = false;
      skipLatestRevCheck = false;
      logger = {
        tail = 100;
        buffer = 5000;
        sinceSeconds = 300;
        fullScreenLogs = false;
        textWrap = false;
        showTime = false;
      };

      thresholds = {
        cpu = {
          critical = 90;
          warn = 70;
        };
        memory = {
          critical = 90;
          warn = 70;
        };
      };
    };

    plugin = {
      plugins = {
        debug = {
          shortCut = "Shift-D";
          description = "Add debug container";
          scopes = [
            "containers"
          ];
          command = "bash";
          background = false;
          confirm = true;
          args = [
            "-c"
            "kubectl debug -it -n=$NAMESPACE $POD --target=$NAME --image=nicolaka/netshoot:v0.11 --share-processes -- bash"
          ];
        };

        toggle-helmrelease = {
          shortCut = "Shift-T";
          confirm = true;
          scopes = [
            "helmreleases"
          ];
          description = "Toggle to suspend or resume a HelmRelease";
          command = "bash";
          background = false;
          args = [
            "-c"
            "flux --context $CONTEXT $([ $(kubectl --context $CONTEXT get helmreleases -n $NAMESPACE $NAME -o=custom-columns=TYPE:.spec.suspend | tail -1) = \"true\" ] && echo \"resume\" || echo \"suspend\") helmrelease -n $NAMESPACE $NAME |& less"
          ];
        };

        toggle-kustomization = {
          shortCut = "Shift-T";
          confirm = true;
          scopes = [
            "kustomizations"
          ];
          description = "Toggle to suspend or resume a Kustomization";
          command = "bash";
          background = false;
          args = [
            "-c"
            "flux --context $CONTEXT $([ $(kubectl --context $CONTEXT get kustomizations -n $NAMESPACE $NAME -o=custom-columns=TYPE:.spec.suspend | tail -1) = \"true\" ] && echo \"resume\" || echo \"suspend\") kustomization -n $NAMESPACE $NAME |& less"
          ];
        };

        reconcile-git = {
          shortCut = "Shift-R";
          confirm = false;
          description = "Flux reconcile";
          scopes = [
            "gitrepositories"
          ];
          command = "bash";
          background = false;
          args = [
            "-c"
            "flux --context $CONTEXT reconcile source git -n $NAMESPACE $NAME |& less"
          ];
        };

        reconcile-hr = {
          shortCut = "Shift-R";
          confirm = false;
          description = "Flux reconcile";
          scopes = [
            "helmreleases"
          ];
          command = "bash";
          background = false;
          args = [
            "-c"
            "flux --context $CONTEXT reconcile helmrelease -n $NAMESPACE $NAME |& less"
          ];
        };

        reconcile-helm-repo = {
          shortCut = "Shift-Z";
          description = "Flux reconcile";
          scopes = [
            "helmrepositories"
          ];
          command = "bash";
          background = false;
          confirm = false;
          args = [
            "-c"
            "flux reconcile source helm --context $CONTEXT -n $NAMESPACE $NAME |& less"
          ];
        };

        reconcile-oci-repo = {
          shortCut = "Shift-Z";
          description = "Flux reconcile";
          scopes = [
            "ocirepositories"
          ];
          command = "bash";
          background = false;
          confirm = false;
          args = [
            "-c"
            "flux reconcile source oci --context $CONTEXT -n $NAMESPACE $NAME |& less"
          ];
        };

        reconcile-ks = {
          shortCut = "Shift-R";
          confirm = false;
          description = "Flux reconcile";
          scopes = [
            "kustomizations"
          ];
          command = "bash";
          background = false;
          args = [
            "-c"
            "flux --context $CONTEXT reconcile kustomization -n $NAMESPACE $NAME |& less"
          ];
        };

        trace = {
          shortCut = "Shift-A";
          confirm = false;
          description = "Flux trace";
          scopes = [
            "all"
          ];
          command = "bash";
          background = false;
          args = [
            "-c"
            "flux --context $CONTEXT trace --kind `echo $RESOURCE_NAME | sed -E 's/ies$/y/' | sed -E 's/ses$/se/' | sed -E 's/(s|es)$//g'` --api-version $RESOURCE_GROUP/$RESOURCE_VERSION --namespace $NAMESPACE $NAME |& less"
          ];
        };

        #get all resources in a namespace using the krew get-all plugin
        # get-all-namespace:
        #   shortCut: g
        #   confirm: false
        #   description: get-all
        #   scopes:
        #     - namespaces
        #   command: sh
        #   background: false
        #   args:
        #     - -c
        #     - "kubectl get all --context $CONTEXT -n $NAME | less"
        #
        # get-all-other:
        #   shortCut: g
        #   confirm: false
        #   description: get-all
        #   scopes:
        #     - all
        #   command: sh
        #   background: false
        #   args:
        #     - -c
        #     - "kubectl get all --context $CONTEXT -n $NAMESPACE | less"
      };
    };
  };
}
