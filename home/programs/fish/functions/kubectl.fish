# Kubernetes/kubectl aliases for Fish
# Based on kube-aliases plugin

# Contexts
alias kcc='kubectl config get-contexts'
alias kctx='kubectx'
alias kns='kubens'

# Core
alias k='kubectl'
alias kc='kubectl'
alias kube='kubectl'
alias kd='kubectl delete'
alias kds='kubectl describe service'
alias ke='kubectl edit'
alias kg='kubectl get'
alias kga='kubectl get --all-namespaces'
alias kl='kubectl logs'
alias kcl='kubectl logs'
alias klf='kubectl logs -f'
alias kaf='kubectl apply -f'
alias kdelf='kubectl delete -f'

# Pods
alias kgp='kubectl get pods'
alias kgpw='watch kubectl get pods'
alias kgpwide='kubectl get pods -o wide'
alias kep='kubectl edit pods'
alias kdp='kubectl delete pods'
alias kdp!='kubectl delete pods --grace-period=0 --force'
alias kgpa='kubectl get pods --all-namespaces'
alias kgpall='kubectl get pods --all-namespaces -o wide'

# Logs
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias klp='kubectl logs -p'

# Deployments
alias kgd='kubectl get deployments'
alias kgdw='watch kubectl get deployments'
alias kgdwide='kubectl get deployments -o wide'
alias ked='kubectl edit deployments'
alias kdd='kubectl delete deployments'
alias ksd='kubectl scale deployment'
alias krsd='kubectl rollout status deployment'
alias kres='kubectl set env deployment'

# Services
alias kgs='kubectl get services'
alias kgsw='watch kubectl get services'
alias kgswide='kubectl get services -o wide'
alias kes='kubectl edit services'
alias kds='kubectl describe services'
alias kdels='kubectl delete services'

# Ingress
alias kgi='kubectl get ingress'
alias kei='kubectl edit ingress'
alias kdi='kubectl describe ingress'
alias kdeli='kubectl delete ingress'

# Namespaces
alias kgns='kubectl get namespaces'
alias kens='kubectl edit namespace'
alias kdns='kubectl describe namespace'
alias kdelns='kubectl delete namespace'

# ConfigMaps
alias kgcm='kubectl get configmaps'
alias kecm='kubectl edit configmap'
alias kdcm='kubectl describe configmap'
alias kdelcm='kubectl delete configmap'

# Secrets
alias kgsec='kubectl get secret'
alias kdsec='kubectl describe secret'
alias kdelsec='kubectl delete secret'

# DaemonSets
alias kgds='kubectl get daemonset'
alias kgdsw='watch kubectl get daemonset'
alias keds='kubectl edit daemonset'
alias kdds='kubectl describe daemonset'
alias kdelds='kubectl delete daemonset'

# StatefulSets
alias kgss='kubectl get statefulset'
alias kgssw='watch kubectl get statefulset'
alias kess='kubectl edit statefulset'
alias kdss='kubectl describe statefulset'
alias kdelss='kubectl delete statefulset'

# CronJobs
alias kgcj='kubectl get cronjob'
alias kecj='kubectl edit cronjob'
alias kdcj='kubectl describe cronjob'
alias kdelcj='kubectl delete cronjob'

# Jobs
alias kgj='kubectl get jobs'
alias kej='kubectl edit job'
alias kdj='kubectl describe job'
alias kdelj='kubectl delete job'

# Nodes
alias kgno='kubectl get nodes'
alias keno='kubectl edit node'
alias kdno='kubectl describe node'
alias kdelno='kubectl delete node'

# PersistentVolumes
alias kgpv='kubectl get pv'
alias kepv='kubectl edit pv'
alias kdpv='kubectl describe pv'
alias kdelpv='kubectl delete pv'

# PersistentVolumeClaims
alias kgpvc='kubectl get pvc'
alias kepvc='kubectl edit pvc'
alias kdpvc='kubectl describe pvc'
alias kdelpvc='kubectl delete pvc'

# ServiceAccounts
alias kgsa='kubectl get serviceaccount'
alias kdsa='kubectl describe serviceaccount'
alias kdelsa='kubectl delete serviceaccount'

# ReplicaSets
alias kgrs='kubectl get rs'
alias kdrs='kubectl describe rs'
alias kers='kubectl edit rs'
alias krrs='kubectl rollout restart rs'

# Rollouts
alias kgro='kubectl get rollout'
alias kdro='kubectl describe rollout'
alias kero='kubectl edit rollout'

# HorizontalPodAutoscalers
alias kghpa='kubectl get hpa'
alias kehpa='kubectl edit hpa'
alias kdhpa='kubectl describe hpa'

# Network Policies
alias kgnp='kubectl get networkpolicy'
alias kenp='kubectl edit networkpolicy'
alias kdnp='kubectl describe networkpolicy'

# Top
alias kt='kubectl top'
alias ktn='kubectl top nodes'
alias ktp='kubectl top pods'

# Exec
function kexec --description "kubectl exec with bash shell"
    kubectl exec -it $argv -- bash
end

function kexecsh --description "kubectl exec with sh shell"
    kubectl exec -it $argv -- sh
end

# Port forward
function kpf --description "kubectl port-forward"
    kubectl port-forward $argv
end

# Get all resources in namespace
function kgall --description "Get all kubernetes resources in namespace"
    kubectl get all $argv
end

# Describe any resource
function kdesc --description "kubectl describe"
    kubectl describe $argv
end

# Watch any resource
function kwatch --description "watch kubectl get"
    watch kubectl get $argv
end

# Apply with dry-run
function kdry --description "kubectl apply with dry-run"
    kubectl apply --dry-run=client -f $argv
end
