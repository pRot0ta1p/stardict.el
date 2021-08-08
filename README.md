# stardict.el

This is a fork of [stardict.el](https://www.emacswiki.org/emacs/download/stardict.el).

This fork trying to improve upon the original script by adding some features:

- [X] Setup helper function
- [ ] Defer the indexing process.
- [ ] Grouping dictionaries by language and switch between groups.

## Dipendency

- f.el (for validating dictionary files.)
- posframe (optional, for popup display.)

## Usage

Add your dictionaries like this:

``` emacs-lisp
(stardict-add-dictionary :lang "Eng"
                         :path "~/.stardict/dic/stardict-lazyworm-ec-2.4.2/"  ;;uncompress you dictionary in folder
                         :filename "lazyworm-ec"
                         :persist t)
```

Then call `stardict-translate-minibuffer` or `stardict-translate-popup` to translate.

## Too Slow?

Before actual searching happens, Emacs have to index the entire dictionary file, this can takes a
few seconds, after indexing process, there should be no freezing-up again.
