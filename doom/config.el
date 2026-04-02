;; Projectile: use alien indexing (no caching, always fresh via fd/git)
(setq projectile-indexing-method 'alien)
(setq projectile-git-use-untracked-files t)

;; Tabs length
(setq-default indent-tabs-mode t)
(setq-default tab-width 4)

;; font
(setq doom-font (font-spec :family "JetBrains Mono" :size 14))
(custom-theme-set-faces!
  'doom-material
  '(org-level-8 :inherit outline-3 :height 1.0)
  '(org-level-7 :inherit outline-3 :height 1.0)
  '(org-level-6 :inherit outline-3 :height 1.1)
  '(org-level-5 :inherit outline-3 :height 1.2)
  '(org-level-4 :inherit outline-3 :height 1.3)
  '(org-level-3 :inherit outline-3 :height 1.4)
  '(org-level-2 :inherit outline-2 :height 1.5)
  '(org-level-1 :inherit outline-1 :height 1.6)
  '(org-document-title :height 1.8 :bold t :underline nil))
(setq doom-theme 'doom-material)

(setq display-line-numbers-type 'relative)

(map! :leader
      :desc "Comment line" "-" #'comment-line)

(setq org-directory "~/org/")
(setq mouse-wheel-follow-mouse 't) ;; scroll window under mouse

(setq confirm-kill-emacs nil)
;; (setq initial-buffer-choice )

(use-package! doom-themes
  :ensure t
  :custom
  ;; Global settings (defaults)
  (doom-themes-enable-bold t)   ; if nil, bold is universally disabled
  (doom-themes-enable-italic t) ; if nil, italics is universally disabled
  ;; for treemacs users
  (doom-themes-treemacs-theme "doom-atom") ; use "doom-colors" for less minimal icon theme
  :config
  ;; Enable flashing mode-line on errors
  (doom-themes-visual-bell-config)
  ;; Enable custom neotree theme (nerd-icons must be installed!)
  (doom-themes-neotree-config)
  ;; or for treemacs users
  (doom-themes-treemacs-config)
  ;; Corrects (and improves) org-mode's native fontification.
  (doom-themes-org-config))

;; Soft-wrap text in scratch, org, and markdown buffers
(add-hook! '(doom-scratch-buffer-created-hook
             org-mode-hook
             markdown-mode-hook
             gfm-mode-hook)
  #'visual-line-mode)

(use-package! ultra-scroll
 :init
 (setq scroll-conservatively 3
       scroll-margin 0)
 :config
 (pixel-scroll-precision-mode 1)  ;; required for pixel-scroll-precision-interpolate
 (ultra-scroll-mode 1))

(defun +custom/scroll-half-page-down ()
  "Smooth animated half-page scroll down."
  (interactive)
  (pixel-scroll-precision-interpolate (- (/ (window-body-height nil t) 2))))

(defun +custom/scroll-half-page-up ()
  "Smooth animated half-page scroll up."
  (interactive)
  (pixel-scroll-precision-interpolate (/ (window-body-height nil t) 2)))

(after! evil
  ;; Bind on `global' keymap so these override any mode-local C-d/C-u bindings
  ;; (comint, vterm, etc.) without needing per-mode overrides.
  (evil-define-key '(normal visual) 'global
    (kbd "C-d") #'+custom/scroll-half-page-down
    (kbd "C-u") #'+custom/scroll-half-page-up))

(setq bash-completion-bash-executable "/opt/homebrew/bin/bash")

(map! :nv "gD" #'+lookup/references)

(after! evil
  (defun +custom/apply-ijkl-core-bindings ()

    ;; Core movement in normal + visual states.
    (define-key evil-normal-state-map (kbd "i") #'evil-previous-line)
    (define-key evil-normal-state-map (kbd "k") #'evil-next-line)
    (define-key evil-normal-state-map (kbd "j") #'evil-backward-char)
    (define-key evil-normal-state-map (kbd "l") #'evil-forward-char)
    (define-key evil-visual-state-map (kbd "i") #'evil-previous-line)
    (define-key evil-visual-state-map (kbd "k") #'evil-next-line)
    (define-key evil-visual-state-map (kbd "j") #'evil-backward-char)
    (define-key evil-visual-state-map (kbd "l") #'evil-forward-char)

    ;; Displaced keys.
    (define-key evil-normal-state-map (kbd ";") #'evil-insert)
    (define-key evil-normal-state-map (kbd ":") #'evil-insert-line)
    (define-key evil-normal-state-map (kbd "K") #'evil-join)
    (define-key evil-visual-state-map (kbd "K") #'evil-join)
    (define-key evil-normal-state-map (kbd "U") #'evil-redo)
    (define-key evil-visual-state-map (kbd "U") #'evil-redo)
    (define-key evil-normal-state-map (kbd "M-;") #'evil-ex)
    (define-key evil-visual-state-map (kbd "M-;") #'evil-ex))

  ;; Apply once now, then re-apply after Doom modules load to win precedence.
  (+custom/apply-ijkl-core-bindings)
  (add-hook 'doom-after-modules-config-hook #'+custom/apply-ijkl-core-bindings))

(after! evil
  ;; Keep Evil disabled in minibuffer/prompt UIs, but force normal-state Evil
  ;; in Dired buffers.
  (set-evil-initial-state! 'dired-mode 'normal)

  ;; Magit stays in Doom's default normal state (via evil-collection).
  ;; IJKL navigation is layered on top via normal-state bindings in the
  ;; Magit section below.

  (add-hook 'dired-mode-hook (lambda () (evil-local-mode 1))))

(defun +custom/window-top-right ()
  "Select the top-right window in the current frame."
  (interactive)
  (let ((best (selected-window))
        (best-right -1))
    (walk-windows
     (lambda (w)
       (let ((edges (window-edges w)))
         (when (and (= (nth 1 edges) 0)            ;; top row
                    (> (nth 2 edges) best-right))   ;; rightmost
           (setq best-right (nth 2 edges)
                 best w))))
     nil (selected-frame))
    (select-window best)))

(map! :map evil-window-map
      "i" #'evil-window-up
      "k" #'evil-window-down
      "j" #'evil-window-left
      "l" #'evil-window-right
      "I" #'+evil/window-move-up
      "K" #'+evil/window-move-down
      "J" #'+evil/window-move-left
      "L" #'+evil/window-move-right
      "t" #'+custom/window-top-right)

(after! magit
  (setq magit-branch-read-upstream-first 'fallback)
  (map! :map magit-mode-map
        :n "i" #'magit-section-backward
        :n "k" #'magit-section-forward
        :n "j" #'magit-section-backward-sibling
        :n "l" #'magit-section-forward-sibling
        :n ";" #'magit-section-toggle))

(after! dired
  (map! :map dired-mode-map
        :nv "i" #'dired-previous-line
        :nv "k" #'dired-next-line
        :nv "j" #'dired-up-directory
        :nv "l" #'dired-find-file))

(after! treemacs
  (map! :map evil-treemacs-state-map
        "i" #'treemacs-previous-line
        "k" #'treemacs-next-line
        "j" #'treemacs-root-up
        "l" #'treemacs-RET-action
        ";" #'treemacs-COLLAPSE-action))

(defvar-local +vterm--user-scrolled-up nil
  "Non-nil when the user has scrolled away from the bottom in a vterm buffer.")

(defun +vterm--check-scroll-position (&rest _)
  "Update `+vterm--user-scrolled-up' based on window position."
  (when (derived-mode-p 'vterm-mode)
    (let ((win (selected-window)))
      (setq +vterm--user-scrolled-up
            (< (window-end win t)
               (- (point-max) (* 2 (window-body-height win))))))))

(defun +vterm-suppress-recenter-a (orig-fn &rest args)
  "Around advice for `recenter': suppress in vterm when user scrolled up."
  (unless (and (derived-mode-p 'vterm-mode)
               +vterm--user-scrolled-up)
    (apply orig-fn args)))

(defun +vterm-suppress-set-window-point-a (orig-fn window point)
  "Around advice for `set-window-point': suppress in vterm when user scrolled up."
  (unless (and (with-current-buffer (window-buffer window)
                 (derived-mode-p 'vterm-mode))
               (buffer-local-value '+vterm--user-scrolled-up (window-buffer window)))
    (funcall orig-fn window point)))

(after! vterm
  ;; Track whether user has scrolled up
  (add-hook 'vterm-mode-hook
    (lambda ()
      (add-hook 'post-command-hook #'+vterm--check-scroll-position nil t)
      (add-hook 'window-scroll-functions
                (lambda (_win _pos) (+vterm--check-scroll-position)) nil t)))

  ;; Advise the two primitives that vterm's C module calls to force scroll
  (advice-add #'recenter :around #'+vterm-suppress-recenter-a)
  (advice-add #'set-window-point :around #'+vterm-suppress-set-window-point-a)

  (evil-define-key 'insert vterm-mode-map
    (kbd "C-r") #'vterm--self-insert)
  (map! :map vterm-mode-map
        :nv "i" #'evil-previous-line
        :nv "k" #'evil-next-line
        :nv "j" #'evil-backward-char
        :nv "l" #'evil-forward-char
        :nv ";" #'evil-insert))

(after! evil-org
  ;; evil-org binds i-prefixed text objects (ie, ip, iR…) in normal state,
  ;; which conflicts with our i=up remap. Remove those normal-state bindings
  ;; so i can stay a plain key, then re-assert IJKL in normal+visual.
  (evil-define-key 'normal evil-org-mode-map
    (kbd "i") nil)
  (map! :map evil-org-mode-map
        :n "i" #'evil-previous-line
        :n "k" #'evil-next-line
        :n "j" #'evil-backward-char
        :n "l" #'evil-forward-char
        :v "i" #'evil-previous-line
        :v "k" #'evil-next-line
        :v "j" #'evil-backward-char
        :v "l" #'evil-forward-char))

;; Force json-mode even after tree-sitter remaps it to json-ts-mode.
;; Use `after!` to ensure our entry is added *after* Doom's tree-sitter
;; module populates the alist, so ours takes precedence (alist = first match wins).
(after! treesit
  (setq major-mode-remap-alist
        (assq-delete-all 'json-mode major-mode-remap-alist))
  (add-to-list 'major-mode-remap-alist '(json-ts-mode . json-mode)))

(after! eglot
  (set-eglot-client! '(json-mode json-ts-mode)
    '("vscode-json-language-server" "--stdio")))

(defun +detect-project-formatter-h ()
  "Set buffer-local formatter to biome when biome.json is found in the project."
  (when (locate-dominating-file default-directory "biome.json")
    (setq-local apheleia-formatter 'biome)))

(add-hook 'typescript-ts-mode-hook #'+detect-project-formatter-h)
(add-hook 'tsx-ts-mode-hook        #'+detect-project-formatter-h)
(add-hook 'js-ts-mode-hook         #'+detect-project-formatter-h)
(add-hook 'json-ts-mode-hook       #'+detect-project-formatter-h)
(add-hook 'jsonc-mode-hook         #'+detect-project-formatter-h)

;; (after! flycheck
;;   (flycheck-define-checker biome-check
;;     "A syntax checker using Biome (biomejs.dev)."
;;     :command ("biome" "check" "--colors=off"
;;               source-original)
;;     :error-patterns
;;     ((warning line-start (file-name) ":" line ":" column " "
;;               (id (one-or-more (not (any " " "\t")))) (zero-or-more not-newline) "\n"
;;               "\n"
;;               "  ! " (message (one-or-more not-newline)) line-end)
;;      (error line-start (file-name) ":" line ":" column " "
;;             "parse" (zero-or-more not-newline) "\n"
;;             "\n"
;;             "  × " (message (one-or-more not-newline)) line-end))
;;     :modes (typescript-ts-mode tsx-ts-mode js-ts-mode json-ts-mode jsonc-mode)
;;     :predicate (lambda () (locate-dominating-file default-directory "biome.json")))

;;   (add-to-list 'flycheck-checkers 'biome-check)
;;   (flycheck-add-next-checker 'eglot-check '(warning . biome-check)))

(defun my/vterm-bottom ()
  (interactive)
  (let ((window (split-window (frame-root-window) -15 'below))
        (dir (or (doom-project-root) default-directory)))
    (select-window window)
    (+vterm/here dir)))

(map! :leader
      :desc "vterm bottom"
      "o t" #'my/vterm-bottom)

(use-package! agent-shell
  :commands (agent-shell
             agent-shell-new-shell
             agent-shell-opencode-start-agent
             agent-shell-anthropic-start-claude-code)
  :init
  ;; Auto-detect personal vs work machine and set the default agent.
  ;; Personal (~/.doom.d): Claude Agent with login-based auth
  ;; Work (~/.config/doom): OpenCode with no API key (uses `opencode auth login` / Cloudflare SSO)
  (if (file-directory-p (expand-file-name "~/.doom.d"))
      (progn
        (setq agent-shell-preferred-agent-config 'claude-code)
        (after! agent-shell-anthropic
          (setq agent-shell-anthropic-authentication
                (agent-shell-anthropic-make-authentication :login t))))
    (progn
      (setq agent-shell-preferred-agent-config 'opencode)
      (after! agent-shell-opencode
        (setq agent-shell-opencode-authentication
              (agent-shell-opencode-make-authentication :none t)))))

  :config
  (require 'acp)

  ;; Prompt to pick an existing session or start new on shell open.
  (setq agent-shell-session-strategy 'prompt)

  ;; Use session/load instead of session/resume so full history is
  ;; streamed back into the buffer when resuming a session.
  (setq agent-shell-prefer-session-resume nil)

  ;; Don't auto-grab the current line as context when opening a shell.
  (setq agent-shell-context-sources '(files region error))

  ;; ---------------------------------------------------------------------------
  ;; Evil keybindings for agent-shell (ijkl-consistent)
  ;; ---------------------------------------------------------------------------

  ;; --- Normal mode -----------------------------------------------------------

  ;; RET sends prompt; ; enters insert mode (consistent with global ijkl config)
  (evil-define-key 'normal agent-shell-mode-map (kbd "RET") #'comint-send-input)
  (evil-define-key 'normal agent-shell-mode-map (kbd ";") #'evil-insert)

  ;; ijkl core movement (i=up, k=down, j=left, l=right) — inherited from global
  ;; but explicitly set to ensure agent-shell-mode-map doesn't shadow them.
  (evil-define-key 'normal agent-shell-mode-map (kbd "i") #'evil-previous-line)
  (evil-define-key 'normal agent-shell-mode-map (kbd "k") #'evil-next-line)
  (evil-define-key 'normal agent-shell-mode-map (kbd "j") #'evil-backward-char)
  (evil-define-key 'normal agent-shell-mode-map (kbd "l") #'evil-forward-char)

  ;; I/K = navigate interactive items (permissions, tool calls, diffs)
  (evil-define-key 'normal agent-shell-mode-map (kbd "I") #'agent-shell-previous-item)
  (evil-define-key 'normal agent-shell-mode-map (kbd "K") #'agent-shell-next-item)

  ;; [ i / ] k = jump between blocks (larger structural navigation)
  (evil-define-key 'normal agent-shell-mode-map (kbd "[ i") #'agent-shell-ui-backward-block)
  (evil-define-key 'normal agent-shell-mode-map (kbd "] k") #'agent-shell-ui-forward-block)

  ;; g[ / g] = jump between prompts in the buffer
  (evil-define-key 'normal agent-shell-mode-map (kbd "g [") #'agent-shell-previous-item)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g ]") #'agent-shell-next-item)

  ;; Input history (M-i = previous, M-k = next)
  (evil-define-key 'normal agent-shell-mode-map (kbd "M-i") #'agent-shell-previous-input)
  (evil-define-key 'normal agent-shell-mode-map (kbd "M-k") #'agent-shell-next-input)

  ;; Session / model management
  (evil-define-key 'normal agent-shell-mode-map (kbd "g m") #'agent-shell-set-session-model)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g s") #'agent-shell-set-session-mode)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g c") #'agent-shell-cycle-session-mode)
  (evil-define-key 'normal agent-shell-mode-map (kbd "M-m") #'agent-shell-cycle-session-mode)

  ;; Session switching
  (evil-define-key 'normal agent-shell-mode-map (kbd "g p") #'agent-shell-resume-session)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g f") #'agent-shell-fork)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g y") #'agent-shell-copy-session-id)

  ;; Shell management
  (evil-define-key 'normal agent-shell-mode-map (kbd "g r") #'agent-shell-search-history)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g o") #'agent-shell-other-buffer)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g t") #'agent-shell-open-transcript)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g l") #'agent-shell-view-traffic)

  ;; Interrupt / clear
  (evil-define-key 'normal agent-shell-mode-map (kbd "C-c") #'agent-shell-interrupt)
  (evil-define-key 'normal agent-shell-mode-map (kbd "g x") #'agent-shell-clear-buffer)

  ;; Toggle fragment expand/collapse at point
  (evil-define-key 'normal agent-shell-mode-map (kbd "TAB") #'agent-shell-ui-toggle-fragment-at-point)

  ;; --- Insert mode -----------------------------------------------------------

  ;; RET sends prompt; S-RET inserts newline for multi-line input
  (evil-define-key 'insert agent-shell-mode-map (kbd "RET") #'comint-send-input)
  (evil-define-key 'insert agent-shell-mode-map (kbd "S-RET") #'newline)

  ;; Input history while typing (M-i = previous, M-k = next)
  (evil-define-key 'insert agent-shell-mode-map (kbd "M-i") #'agent-shell-previous-input)
  (evil-define-key 'insert agent-shell-mode-map (kbd "M-k") #'agent-shell-next-input)

  ;; Cycle session mode (M-m = mode)
  (evil-define-key 'insert agent-shell-mode-map (kbd "M-m") #'agent-shell-cycle-session-mode)

  ;; Interrupt from insert mode
  (evil-define-key 'insert agent-shell-mode-map (kbd "C-c") #'agent-shell-interrupt)

  ;; --- Visual mode -----------------------------------------------------------
  (evil-define-key 'visual agent-shell-mode-map (kbd "i") #'evil-previous-line)
  (evil-define-key 'visual agent-shell-mode-map (kbd "k") #'evil-next-line)
  (evil-define-key 'visual agent-shell-mode-map (kbd "j") #'evil-backward-char)
  (evil-define-key 'visual agent-shell-mode-map (kbd "l") #'evil-forward-char)

  ;; --- Diff buffers: start in emacs state so y/n/p/q keys work directly ------
  (add-hook 'diff-mode-hook
            (lambda ()
              (when (string-match-p "\\*agent-shell-diff\\*" (buffer-name))
                (evil-emacs-state))))

  ;; --- Viewport mode (read-only response viewer) -----------------------------
  (with-eval-after-load 'agent-shell-viewport
    (evil-define-key 'normal agent-shell-viewport-view-mode-map
      (kbd "i") #'evil-previous-line
      (kbd "k") #'evil-next-line
      (kbd "j") #'evil-backward-char
      (kbd "l") #'evil-forward-char
      (kbd "I") #'agent-shell-viewport-previous-page
      (kbd "K") #'agent-shell-viewport-next-page
      (kbd "M-i") #'agent-shell-viewport-previous-item
      (kbd "M-k") #'agent-shell-viewport-next-item
      (kbd "g m") #'agent-shell-viewport-set-session-model
      (kbd "g s") #'agent-shell-viewport-set-session-mode
      (kbd "g o") #'agent-shell-other-buffer
      (kbd "C-c") #'agent-shell-viewport-interrupt
      (kbd "r") #'agent-shell-viewport-reply
      (kbd "R") #'agent-shell-viewport-refresh
      (kbd "q") #'quit-window))

  ;; --- Notification when agent-shell turn completes --------------------------
  (add-hook 'agent-shell-mode-hook
    (lambda ()
      (agent-shell-subscribe-to
       :shell-buffer (current-buffer)
       :event 'turn-complete
       :on-event (lambda (_event)
                   (start-process "ping" nil "afplay" "/System/Library/Sounds/Ping.aiff")
                   (start-process "notify" nil "osascript" "-e"
                     "display notification \"Turn complete\" with title \"Agent Shell\""))))))

;; ---------------------------------------------------------------------------
;; Leader keybindings for agent-shell
;; ---------------------------------------------------------------------------
(map! :leader
      (:prefix ("o" . "open")
       :desc "Agent Shell"     "c" #'agent-shell
       :desc "New Agent Shell" "C" #'agent-shell-new-shell)
      (:prefix ("A" . "agent")
       :desc "Agent Shell"         "a" #'agent-shell
       :desc "New shell"           "n" #'agent-shell-new-shell
       :desc "Restart shell"       "r" #'agent-shell-restart
       :desc "Fork session"        "f" #'agent-shell-fork
       :desc "Set model"           "m" #'agent-shell-set-session-model
       :desc "Set mode"            "s" #'agent-shell-set-session-mode
       :desc "Compose prompt"      "c" #'agent-shell-prompt-compose
       :desc "Send region"         "e" #'agent-shell-send-region
       :desc "Send file"           "F" #'agent-shell-send-current-file
       :desc "Send DWIM"           "d" #'agent-shell-send-dwim
       :desc "Toggle shell"        "t" #'agent-shell-toggle
       :desc "View transcript"     "T" #'agent-shell-open-transcript
       :desc "View traffic"        "l" #'agent-shell-view-traffic
       :desc "Interrupt"           "x" #'agent-shell-interrupt
       :desc "Rename buffer"       "R" #'agent-shell-rename-buffer
       :desc "Resume session"      "p" #'agent-shell-resume-session
       :desc "Copy session ID"     "y" #'agent-shell-copy-session-id))

(use-package! olivetti
  :config
  (setq olivetti-body-width 0.9)
  (add-hook 'org-mode-hook #'olivetti-mode))

(map! :leader
      :desc "Toggle olivetti padding" "t o" #'olivetti-mode)

(use-package! copilot
  :hook (prog-mode . copilot-mode)
  :bind (:map copilot-completion-map
              ("<tab>" . 'copilot-accept-completion)
              ("TAB" . 'copilot-accept-completion)
              ("C-TAB" . 'copilot-accept-completion-by-word)
              ("C-<tab>" . 'copilot-accept-completion-by-word)
              ("C-n" . 'copilot-next-completion)
              ("C-p" . 'copilot-previous-completion))

  :config
    (add-to-list 'copilot-indentation-alist '(prog-mode 4))
    (add-to-list 'copilot-indentation-alist '(org-mode 4))
    (add-to-list 'copilot-indentation-alist '(text-mode 4))
    (add-to-list 'copilot-indentation-alist '(clojure-mode 4))
    (add-to-list 'copilot-indentation-alist '(emacs-lisp-mode 4))
  )
