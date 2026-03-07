;; Tabs length
(setq-default indent-tabs-mode t)
(setq-default tab-width 4)

;; font
(setq doom-font (font-spec :size 14))
(custom-theme-set-faces!
  'doom-dracula
  '(org-level-8 :inherit outline-3 :height 1.0)
  '(org-level-7 :inherit outline-3 :height 1.0)
  '(org-level-6 :inherit outline-3 :height 1.1)
  '(org-level-5 :inherit outline-3 :height 1.2)
  '(org-level-4 :inherit outline-3 :height 1.3)
  '(org-level-3 :inherit outline-3 :height 1.4)
  '(org-level-2 :inherit outline-2 :height 1.5)
  '(org-level-1 :inherit outline-1 :height 1.6)
  '(org-document-title :height 1.8 :bold t :underline nil))
(setq doom-theme 'doom-dracula)

(setq display-line-numbers-type 'relative)

(map! :leader
      :desc "Comment line" "-" #'comment-line)

(setq org-directory "~/org/")

(setq confirm-kill-emacs nil)
;; (setq initial-buffer-choice )

(setq bash-completion-bash-executable "/opt/homebrew/bin/bash")

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

  ;; Use Emacs state for Magit so that all native magit keybindings (s, p, c,
  ;; F, b, d, etc.) work out of the box.  Our IJKL navigation is layered on
  ;; top via emacs-state bindings in the Magit section below.
  ;; (set-evil-initial-state! '(magit-mode
  ;;                            magit-status-mode
  ;;                            magit-revision-mode
  ;;                            magit-diff-mode
  ;;                            magit-process-mode)
  ;;                          'emacs)

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
  (define-key magit-mode-map (kbd "SPC") nil)
  (evil-define-key 'emacs magit-mode-map
    (kbd "i") #'magit-section-backward
    (kbd "k") #'magit-section-forward
    (kbd "j") #'magit-section-backward-sibling
    (kbd "l") #'magit-section-forward-sibling
    (kbd ";") #'magit-section-toggle))

(after! dired
  (map! :map dired-mode-map
        :nv "i" #'dired-previous-line
        :nv "k" #'dired-next-line
        :nv "j" #'dired-up-directory
        :nv "l" #'dired-find-file))

(after! vterm
  (evil-define-key 'insert vterm-mode-map
    (kbd "C-r") #'vterm--self-insert))

(after! evil-org
  (map! :map evil-org-mode-map
        :nv "i" #'evil-previous-line
        :nv "k" #'evil-next-line
        :nv "j" #'evil-backward-char
        :nv "l" #'evil-forward-char))

(after! json-ts-mode
  (setf (alist-get 'json-mode major-mode-remap-defaults) nil))

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

(defun +custom/open-code-terminal ()
  "Open opencode in a new right-most split."
  (interactive)
  ;; Find the right-most window in the current frame.
  (let* ((rightmost-window
          (let ((best (selected-window))
                (best-right -1))
            (dolist (win (window-list nil 'nomini) best)
              (let ((right (nth 2 (window-edges win))))
                (when (> right best-right)
                  (setq best-right right
                        best win))))))
         (target-width 100)
         (evil-vsplit-window-right t))
    (select-window rightmost-window)
    ;; 1. Split at the right-most edge.
    (evil-window-vsplit)
    ;; 3. Resize the new window to a fixed width.
    (window-resize (selected-window)
                   (- target-width (window-total-width))
                   t)
    ;; 4. Open vterm in this new window.
    (+vterm/here nil)
    ;; 5. Start opencode.
    (vterm-send-string "opencode")
    (vterm-send-return)))

;; Now, let's bind it to a Leader key.
;; Since it's a 'code' related terminal, 'SPC o c' (Open Code) is a good fit.
(map! :leader
      (:prefix ("o" . "open")
       :desc "Open Code Terminal" "c" #'+custom/open-code-terminal))
