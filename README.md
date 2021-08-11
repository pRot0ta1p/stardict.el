# stardict.el

This is a fork of [stardict.el](https://www.emacswiki.org/emacs/download/stardict.el).

This fork trying to improve upon the original script by adding some features:

- [X] Setup helper function
- [X] Defer the indexing process.
- [ ] Filter the dictionaries by language.

## Dependency

- f.el
- cl-lib
- posframe

## Usage

Add this script to your `load-path`

``` emacs-lisp
(add-to-list 'load-path "\path\to\stadict.el")
```


Add your dictionaries like this:

``` emacs-lisp
(stardict-add-dictionary :lang "Eng"
                         :path "~/.stardict/dic/stardict-lazyworm-ec-2.4.2/"  ;;uncompress you dictionary in folder
                         :filename "lazyworm-ec"
                         :persist t) ;; persist means Emacs will load the dictionary file in a buffer as read-only, until you close it
```

Then call `stardict-translate-minibuffer` or `stardict-translate-popup` to translate.

## Customization

`M-x customize-group RET` to get a list of customizable options.

## Loading too Slow?

Before actual searching happens, Emacs have to index the entire dictionary file, this happens when `stardic-add-dictionary` is called.
this can takes a few seconds, after indexing process, there should be no freezing-up again.

If you just can't stand the indexing because its blocking, you can defer it to the very fist time
you call an arbitrary function, with a macro provided by `stardict.el` called `stardict-defer-load`.

One obvious choise is defer the indexing right before you invoke any of the interactive translation functions, like this:

``` emacs-lisp
 (stardict-defer-load '(stardict-translate-popup stardict-translate-minibuffer)
	(stardict-add-dictionary :lang "Eng"
                             :path "~/bin/sdcv/stardict-lazyworm-ec-2.4.2"
                             :filename "lazyworm-ec"
                             :persist t)
    (stardict-add-dictionary :lang "Eng"
                             :path "~/bin/sdcv/stardict-oxford-gb-formated-2.4.2"
                             :filename "oxford-gb-formated"
                             :persist t))

;; basic usage of `stardict-defer-load' is
(stardict-defer-load '(list of function)
  (abitrary forms to eval when any of the functions is invoked for the first time))
```

See the docstring of `stardict-defer-load` for details.
