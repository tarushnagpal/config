# Shell wrappers for the Proximal worktree/Zellij workflow.
# Keep host-specific environment and unrelated aliases in ~/.zshrc.

nwt() { "$HOME/.config/zellij/new-worktree.sh" "$@"; }
owt() { "$HOME/.config/zellij/open-origin-worktree.sh" "$@"; }
rmwt() { "$HOME/.config/zellij/remove-worktree.sh" "$@"; }
wtsetup() { "$HOME/.config/zellij/run-worktree-setup.sh" "$@"; }
gclone() { "$HOME/.config/zellij/clone-worktree-container.sh" "$@"; }

# Start a new registered Pi pane in the current cwd. This is useful after the
# user has placed a pane manually with Zellij; fork-to-pane uses the launcher
# directly and does not need this wrapper.
piw() { "$HOME/.config/zellij/open-worktree-pi.sh" --new "$@"; }
