" vim:foldmethod=marker:fen:
scriptencoding utf-8

" See 'plugin/eskk.vim' about the license.

" Load once {{{
if exists('s:loaded')
    finish
endif
let s:loaded = 1
" }}}
" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}
runtime! plugin/eskk.vim

augroup eskk
autocmd!

" s:eskk {{{
" mode: Current mode.
" buftable: Buffer strings for inserted, filtered and so on.
" is_locked_old_str: Lock current diff old string?
" temp_event_hook_fn: Temporary event handler functions/arguments.
" enabled: True if s:eskk.enable() is called.
let s:eskk = {
\   'mode': '',
\   'buftable': eskk#buftable#new(),
\   'is_locked_old_str': 0,
\   'temp_event_hook_fn': {},
\   'enabled': 0,
\   'stash': {},
\}

function! s:eskk_new() "{{{
    return deepcopy(s:eskk, 1)
endfunction "}}}

" Enable/Disable IM
function! s:eskk.enable(...) dict "{{{
    let do_map = a:0 != 0 ? a:1 : 1

    if self.is_enabled()
        return ''
    endif
    call eskk#util#log('enabling eskk...')

    " If skk.vim exists and enabled, disable it.
    let disable_skk_vim = ''
    if exists('g:skk_version') && exists('b:skk_on') && b:skk_on
        let disable_skk_vim = SkkDisable()
    endif


    " Clear current variable states.
    let self.mode = ''
    call self.buftable.reset()


    " Set up Mappings.
    if do_map
        call self.map_all_keys()
    endif


    " TODO Save previous mode/state.
    call self.set_mode(g:eskk_initial_mode)

    call self.call_mode_func('cb_im_enter', [], 0)

    let self.enabled = 1
    return disable_skk_vim . "\<C-^>"
endfunction "}}}
function! s:eskk.disable(...) dict "{{{
    let do_unmap = a:0 != 0 ? a:1 : 0

    if !self.is_enabled()
        return ''
    endif
    call eskk#util#log('disabling eskk...')

    if do_unmap
        call self.unmap_all_keys()
    endif

    call self.call_mode_func('cb_im_leave', [], 0)

    let self.enabled = 0

    let kakutei_str = eskk#kakutei_str()
    call self.buftable.reset()
    return kakutei_str . "\<C-^>"
endfunction "}}}
function! s:eskk.toggle() dict "{{{
    return self[self.is_enabled() ? 'disable' : 'enable']()
endfunction "}}}
function! s:eskk.is_enabled() dict "{{{
    return self.enabled
endfunction "}}}

" Mappings
function! s:eskk.map_all_keys(...) dict "{{{
    if s:has_mapped
        return
    endif


    lmapclear <buffer>

    " Map mapped keys.
    for key in g:eskk_mapped_key
        call call('eskk#set_up_key', [key] + a:000)
    endfor

    " Map escape key.
    execute
    \   'lnoremap'
    \   '<buffer><expr>' . (a:0 ? s:mapopt_chars2raw(a:1) : '')
    \   s:map.escape.lhs
    \   'eskk#escape_key()'

    " Map `:EskkMap -general` keys.
    for [key, opt] in items(s:map.general)
        if opt.rhs == ''
            call s:map_key(key, opt.options)
        else
            execute
            \   printf('l%smap', (opt.options.remap ? '' : 'nore'))
            \   '<buffer>' . s:mapopt_dict2raw(opt.options)
            \   key
            \   opt.rhs
        endif
    endfor

    let s:has_mapped = 1
endfunction "}}}
function! s:eskk.unmap_all_keys() dict "{{{
    if !s:has_mapped
        return
    endif

    for key in g:eskk_mapped_key
        call eskk#unmap_key(key)
    endfor
    let s:has_mapped = 0
endfunction "}}}

" Manipulate display string.
function! s:eskk.remove_display_str() dict "{{{
    let current_str = self.buftable.get_display_str()
    return repeat("\<C-h>", eskk#util#mb_strlen(current_str))
endfunction "}}}
function! s:eskk.kakutei_str() dict "{{{
    return self.remove_display_str() . self.buftable.get_display_str(0)
endfunction "}}}

" Sticky key
function! s:eskk.get_sticky_key() dict "{{{
    return s:map.sticky.lhs
endfunction "}}}
function! s:eskk.get_sticky_char() dict "{{{
    return eskk#util#eval_key(self.get_sticky_key())
endfunction "}}}
function! s:eskk.is_sticky_key(char) dict "{{{
    " TODO Cache result of eskk#util#eval_key() ?
    return eskk#util#eval_key(s:map.sticky.lhs) ==# a:char
endfunction "}}}
function! s:eskk.sticky_key(stash) dict "{{{
    return self.buftable.step_henkan_phase(a:stash)
endfunction "}}}

" Henkan key
function! s:eskk.get_henkan_key() dict "{{{
    return s:map.henkan.lhs
endfunction "}}}
function! s:eskk.get_henkan_char() dict "{{{
    return eskk#util#eval_key(self.get_henkan_key())
endfunction "}}}
function! s:eskk.is_henkan_key(char) dict "{{{
    " TODO Cache result of eskk#util#eval_key() ?
    return eskk#util#eval_key(s:map.henkan.lhs) ==# a:char
endfunction "}}}

" Big letter keys
function! s:eskk.is_big_letter(char) dict "{{{
    return a:char =~# '^[A-Z]$'
endfunction "}}}

" Escape key
function! s:eskk.escape_key() dict "{{{
    let kakutei_str = self.kakutei_str()
    call self.buftable.reset()
    return kakutei_str . "\<Esc>"
endfunction "}}}

" Mode
function! s:eskk.set_mode(next_mode) dict "{{{
    call eskk#util#logf("mode change: %s => %s", self.mode, a:next_mode)
    if !self.is_supported_mode(a:next_mode)
        call eskk#util#warnf("mode '%s' is not supported.", a:next_mode)
        call eskk#util#warnf('s:available_modes = %s', string(s:available_modes))
        return
    endif

    call self.throw_event('leave-mode-' . self.mode)

    " Change mode.
    let prev_mode = self.mode
    let self.mode = a:next_mode

    " Reset buftable.
    call self.buftable.reset()

    " cb_mode_enter
    call self.call_mode_func('cb_mode_enter', [self.mode], 0)

    call self.throw_event('enter-mode-' . self.mode)

    " For &statusline.
    redrawstatus
endfunction "}}}
function! s:eskk.get_mode() dict "{{{
    return self.mode
endfunction "}}}
function! s:eskk.is_supported_mode(mode) dict "{{{
    return has_key(s:available_modes, a:mode)
endfunction "}}}
function! s:eskk.register_mode(mode, ...) dict "{{{
    let mode_self = a:0 != 0 ? a:1 : {}
    let s:available_modes[a:mode] = mode_self
endfunction "}}}
function! s:eskk.validate_mode_structure(mode) dict "{{{
    " It should be good to call this function at the end of mode register.

    let st = self.get_mode_structure(a:mode)

    for key in ['filter']
        if !has_key(st, key)
            throw eskk#user_error(['eskk'], printf("eskk#register_mode(%s): %s is not present in structure", string(a:mode), string(key)))
        endif
    endfor
endfunction "}}}
function! s:eskk.get_mode_structure(mode) dict "{{{
    if !self.is_supported_mode(a:mode)
        throw eskk#user_error(['eskk'], printf("mode '%s' is not available.", a:mode))
    endif
    return s:available_modes[a:mode]
endfunction "}}}
function! s:eskk.call_mode_func(func_key, args, required) dict "{{{
    let st = self.get_mode_structure(self.mode)
    if !has_key(st, a:func_key)
        if a:required
            let msg = printf("Mode '%s' does not have required function key", self.mode)
            throw eskk#internal_error(['eskk'], msg)
        endif
        return
    endif
    return call(st[a:func_key], a:args, st)
endfunction "}}}

" Statusline
function! s:eskk.get_stl() dict "{{{
    " TODO Add these strings to each mode structure.
    let mode_str = {'hira': 'あ', 'kata': 'ア', 'ascii': 'a', 'zenei': 'ａ'}
    return self.is_enabled() ? printf('[eskk:%s]', get(mode_str, self.mode, '??')) : ''
endfunction "}}}

" Buftable
function! s:eskk.get_buftable() dict "{{{
    return self.buftable
endfunction "}}}
function! s:eskk.set_buftable(buftable) dict "{{{
    call a:buftable.set_old_str(self.buftable.get_old_str())
    let self.buftable = a:buftable
endfunction "}}}
function! s:eskk.rewrite() dict "{{{
    return self.buftable.rewrite()
endfunction "}}}

" Event
function! s:eskk.register_event(event_names, Fn, head_args) dict "{{{
    let args = [s:event_hook_fn, a:event_names, a:Fn, a:head_args, (a:0 ? a:1 : -1)]
    return call('s:register_event', args)
endfunction "}}}
function! s:eskk.register_temp_event(event_names, Fn, head_args, ...) dict "{{{
    let args = [self.temp_event_hook_fn, a:event_names, a:Fn, a:head_args, (a:0 ? a:1 : -1)]
    return call('s:register_event', args)
endfunction "}}}
function! s:register_event(st, event_names, Fn, head_args, self) "{{{
    for name in (type(a:event_names) == type([]) ? a:event_names : [a:event_names])
        if !has_key(a:st, name)
            let a:st[name] = []
        endif
        call add(a:st[name], [a:Fn, a:head_args] + (a:self !=# -1 ? [a:self] : []))
    endfor
endfunction "}}}
function! s:eskk.has_events(event_name) dict "{{{
    return
    \   has_key(s:event_hook_fn, a:event_name)
    \   || has_key(self.temp_event_hook_fn, a:event_name)
endfunction "}}}
function! s:eskk.throw_event(event_name) dict "{{{
    call eskk#util#log("Do event - " . a:event_name)

    let ret        = []
    let event      = get(s:event_hook_fn, a:event_name, [])
    let temp_event = get(self.temp_event_hook_fn, a:event_name, [])
    for call_args in event + temp_event
        call add(ret, call('call', call_args))
    endfor

    " Clear temporary hooks.
    let self.temp_event_hook_fn[a:event_name] = []

    return ret
endfunction "}}}

" Locking diff old string
function! s:eskk.lock_old_str() dict "{{{
    let self.is_locked_old_str = 1
endfunction "}}}
function! s:eskk.unlock_old_str() dict "{{{
    let self.is_locked_old_str = 0
endfunction "}}}

" Dispatch functions
function! s:eskk.filter(char) dict "{{{
    return s:filter(self, a:char, 's:filter_body_call_mode_or_default_filter', [self])
endfunction "}}}
function! s:eskk.call_via_filter(Fn, head_args, ...) dict "{{{
    let char = a:0 != 0 ? a:1 : ''
    return s:filter(self, char, a:Fn, a:head_args)
endfunction "}}}
function! s:filter(self, char, Fn, head_args) "{{{
    let self = a:self

    call eskk#util#logf('a:char = %s(%d)', a:char, char2nr(a:char))
    if !self.is_supported_mode(self.mode)
        call eskk#util#warn('current mode is empty!')
        sleep 1
    endif


    call self.throw_event('filter-begin')

    let filter_args = [{
    \   'char': a:char,
    \   'return': 0,
    \}]

    if !self.is_locked_old_str
        call self.buftable.set_old_str(self.buftable.get_display_str())
    endif

    try
        call call(a:Fn, a:head_args + filter_args)

        let ret_str = filter_args[0].return
        if type(ret_str) == type("")
            return ret_str
        else
            " NOTE: Because of Vim's bug, `:lmap` can't remap to `:lmap`.
            execute
            \   'map!'
            \   '<buffer><expr>'
            \   '<Plug>(eskk:_filter_redispatch)'
            \   (self.has_events('filter-redispatch') ?
            \       'join(eskk#throw_event("filter-redispatch"))'
            \       : '""')

            return
            \   self.rewrite()
            \   . "\<Plug>(eskk:_filter_redispatch)"
        endif

    catch
        " TODO Show v:exception only once in current mode.
        " TODO Or open another buffer for showing this annoying messages.
        "
        " sleep 1
        "
        call eskk#util#warn('!!!!!!!!!!!!!! error !!!!!!!!!!!!!!')
        call eskk#util#warn('--- exception ---')
        call eskk#util#warnf('v:exception: %s', v:exception)
        call eskk#util#warnf('v:throwpoint: %s', v:throwpoint)
        call eskk#util#warn('--- buftable ---')
        call self.buftable.dump_print()
        call eskk#util#warn('--- char ---')
        call eskk#util#warnf('char: %s', a:char)
        call eskk#util#warn('!!!!!!!!!!!!!! error !!!!!!!!!!!!!!')

        return self.escape_key() . a:char

    finally
        call self.throw_event('filter-finalize')
    endtry
endfunction "}}}
function! s:filter_body_call_mode_or_default_filter(self, stash) "{{{
    let self = a:self
    call self.call_mode_func('filter', [a:stash], 1)
endfunction "}}}

" Misc.

" s:map related functions.
" TODO Move this to s:map
function! s:eskk.is_special_lhs(char, type) dict "{{{
    return has_key(s:map, a:type)
    \   && eskk#util#eval_key(s:map[a:type].lhs) ==# a:char
endfunction "}}}
function! s:eskk.get_special_key(type) dict "{{{
    if has_key(s:map, a:type)
        return s:map[a:type].lhs
    else
        throw eskk#internal_error(['eskk'], "Unknown map type: " . a:type)
    endif
endfunction "}}}

lockvar s:eskk
" }}}

" Variables {{{

" These instances are created, destroyed
" at word-register mode.
let s:eskk_instances = [s:eskk_new()]
" Index number of s:eskk_instances for current instance.
let s:instance_id = 0

" NOTE: Following variables are non-local between instances.

" Supported modes and their structures.
let s:available_modes = {}
" Database for misc. keys.
let s:map = {
\   'general': {},
\   'sticky': {},
\   'henkan': {},
\   'escape': {},
\   'henkan-select:choose-next': {},
\   'henkan-select:choose-prev': {},
\   'henkan-select:next-page': {},
\   'henkan-select:prev-page': {},
\   'mode:hira:toggle-hankata': {},
\   'mode:hira:ctrl-q-key': {},
\   'mode:hira:toggle-kata': {},
\   'mode:hira:q-key': {},
\   'mode:hira:to-ascii': {},
\   'mode:hira:to-zenei': {},
\   'mode:kata:toggle-hankata': {},
\   'mode:kata:ctrl-q-key': {},
\   'mode:kata:toggle-kata': {},
\   'mode:kata:q-key': {},
\   'mode:kata:to-ascii': {},
\   'mode:kata:to-zenei': {},
\   'mode:hankata:toggle-hankata': {},
\   'mode:hankata:ctrl-q-key': {},
\   'mode:hankata:toggle-kata': {},
\   'mode:hankata:q-key': {},
\   'mode:hankata:to-ascii': {},
\   'mode:hankata:to-zenei': {},
\   'mode:ascii:to-hira': {},
\   'mode:zenei:to-hira': {},
\}
" Same structure as `s:eskk.stash`, but this is set by `s:mutable_stash.init()`.
let s:stash_prototype = {}
" Event handler functions/arguments.
let s:event_hook_fn = {}
" `s:eskk.map_all_keys()` and `s:eskk.unmap_all_keys()` toggle this value.
let s:has_mapped = 0
" }}}

" Functions {{{

function! eskk#load() "{{{
    runtime! plugin/eskk.vim
endfunction "}}}



" These mapping functions actually map key using ":lmap".
function! eskk#set_up_key(key, ...) "{{{
    if a:0
        return s:map_key(a:key, s:mapopt_chars2dict(a:1))
    else
        return s:map_key(a:key, s:create_default_mapopt())
    endif
endfunction "}}}
function! s:map_key(key, options) "{{{
    " Assumption: a:key must be '<Bar>' not '|'.

    " Map a:key.
    let named_key = eskk#get_named_map(a:key)
    execute
    \   'lmap'
    \   '<buffer>' . s:mapopt_dict2raw(a:options)
    \   a:key
    \   named_key
endfunction "}}}
function! eskk#set_up_temp_key(lhs, ...) "{{{
    " Assumption: a:lhs must be '<Bar>' not '|'.

    " Save current a:lhs mapping.
    if maparg(a:lhs, 'l') != ''
        " TODO Check if a:lhs is buffer local.
        call eskk#util#log('Save temp key: ' . maparg(a:lhs, 'l'))
        execute
        \   'lmap'
        \   '<buffer>'
        \   s:temp_key_map(a:lhs)
        \   maparg(a:lhs, 'l')
    endif

    if a:0
        execute
        \   'lmap'
        \   '<buffer>'
        \   a:lhs
        \   a:1
    else
        call eskk#set_up_key(a:lhs)
    endif
endfunction "}}}
function! eskk#set_up_temp_key_restore(lhs) "{{{
    let temp_key = s:temp_key_map(a:lhs)
    let saved_rhs = maparg(temp_key, 'l')

    if saved_rhs != ''
        call eskk#util#log('Restore saved temp key: ' . saved_rhs)
        execute 'lunmap <buffer>' temp_key
        execute 'lmap <buffer>' a:lhs saved_rhs
    else
        call eskk#util#logf("warning: called eskk#set_up_temp_key_restore() but no '%s' key is stashed.", a:lhs)
        call eskk#set_up_key(a:lhs)
    endif
endfunction "}}}
function! eskk#has_temp_key(lhs) "{{{
    let temp_key = s:temp_key_map(a:lhs)
    let saved_rhs = maparg(temp_key, 'l')
    return saved_rhs != ''
endfunction "}}}
function! eskk#unmap_key(key) "{{{
    " Assumption: a:key must be '<Bar>' not '|'.

    " Unmap a:key.
    execute
    \   'lunmap'
    \   '<buffer>'
    \   a:key

    " TODO Restore buffer local mapping?
endfunction "}}}
function! s:temp_key_map(key) "{{{
    return printf('<Plug>(eskk:prevmap:%s)', a:key)
endfunction "}}}
function! eskk#get_named_map(key) "{{{
    " NOTE:
    " a:key is escaped. So when a:key is '<C-a>', return value is
    "   `<Plug>(eskk:filter:<C-a>)`
    " not
    "   `<Plug>(eskk:filter:^A)` (^A is control character)

    let lhs = printf('<Plug>(eskk:filter:%s)', a:key)
    if maparg(lhs, 'l') != ''
        return lhs
    endif

    " XXX: :lmap can't remap. It's possibly Vim's bug.
    " So I also prepare :noremap! mappings.
    " execute
    " \   'lmap'
    " \   '<expr>'
    " \   lhs
    " \   printf('eskk#filter(%s)', string(a:key))
    execute
    \   'map!'
    \   '<expr>'
    \   lhs
    \   printf('eskk#filter(%s)', string(a:key))

    return lhs
endfunction "}}}

" eskk#map()
function! eskk#map(type, options, lhs, rhs) "{{{
    return s:create_map(eskk#get_current_instance(), a:type, s:mapopt_chars2dict(a:options), a:lhs, a:rhs, 'eskk#map()')
endfunction "}}}
function! s:create_map(self, type, options, lhs, rhs, from) "{{{
    let self = a:self
    let lhs = a:lhs
    let rhs = a:rhs

    if !has_key(s:map, a:type)
        call eskk#util#warn('%s: unknown type: %s', a:from, a:type)
        return
    endif
    let type_st = s:map[a:type]

    if a:type ==# 'general'
        if lhs == ''
            call eskk#util#warn("lhs must not be empty string.")
            return
        endif
        if has_key(type_st, lhs) && a:options.unique
            call eskk#util#warnf("%s: Already mapped to '%s'.", a:from, lhs)
            return
        endif
        let type_st[lhs] = {
        \   'options': a:options,
        \   'rhs': rhs
        \}
    else
        if a:options.unique && has_key(type_st, 'lhs')
            let msg = printf('%s: -unique is specified and mapping already exists. skip.', a:type)
            call eskk#util#warn(msg)
            return
        endif
        let type_st.options = a:options
        let type_st.lhs = lhs
    endif
endfunction "}}}
function! s:mapopt_chars2dict(options) "{{{
    let opt = s:create_default_mapopt()
    for c in split(a:options, '\zs')
        if c ==# 'b'
            let opt.buffer = 1
        elseif c ==# 'e'
            let opt.expr = 1
        elseif c ==# 's'
            let opt.silent = 1
        elseif c ==# 'u'
            let opt.unique = 1
        elseif c ==# 'r'
            let opt.remap = 1
        endif
    endfor
    return opt
endfunction "}}}
function! s:mapopt_dict2raw(options) "{{{
    let ret = ''
    for [key, val] in items(a:options)
        if key ==# 'remap'
            continue
        endif
        if val
            let ret .= printf('<%s>', key)
        endif
    endfor
    return ret
endfunction "}}}
function! s:mapopt_chars2raw(options) "{{{
    return s:mapopt_dict2raw(s:mapopt_chars2dict(a:options))
endfunction "}}}
function! s:create_default_mapopt() "{{{
    return {
    \   'buffer': 0,
    \   'expr': 0,
    \   'silent': 0,
    \   'unique': 0,
    \   'remap': 0,
    \}
endfunction "}}}

" :EskkMap - Ex command for eskk#map()
function! s:skip_white(args) "{{{
    return substitute(a:args, '^\s*', '', '')
endfunction "}}}
function! s:parse_one_arg_from_q_args(args) "{{{
    let arg = s:skip_white(a:args)
    let head = matchstr(arg, '^.\{-}[^\\]\ze\([ \t]\|$\)')
    let rest = strpart(arg, strlen(head))
    return [head, rest]
endfunction "}}}
function! s:parse_options(args) "{{{
    let args = a:args
    let type = 'general'
    let opt = s:create_default_mapopt()
    let opt.noremap = 0

    while !empty(args)
        let [a, rest] = s:parse_one_arg_from_q_args(args)
        if a[0] !=# '-'
            break
        endif
        let args = rest

        if a ==# '--'
            break
        elseif a[0] ==# '-'
            if a[1:] ==# 'expr'
                let opt.expr = 1
            elseif a[1:] ==# 'noremap'
                let opt.noremap = 1
            elseif a[1:] ==# 'buffer'
                let opt.buffer = 1
            elseif a[1:] ==# 'silent'
                let opt.silent = 1
            elseif a[1:] ==# 'special'
                let opt.special = 1
            elseif a[1:] ==# 'script'
                let opt.script = 1
            elseif a[1:] ==# 'unique'
                let opt.unique = 1
            elseif a[1:4] ==# 'type'
                if a =~# '^-type='
                    " TODO Allow -type="..." style?
                    " But I don't suppose that -type's argument cotains whitespaces.
                    let type = substitute(a, '^-type=', '', '')
                else
                    throw eskk#parse_error(['eskk'], "-type must be '-type=...' style.")
                endif
            else
                throw eskk#parse_error(['eskk'], printf("unknown option '%s'.", a))
            endif
        endif
    endwhile

    let opt.remap = !opt.noremap
    call remove(opt, 'noremap')
    return [opt, type, args]
endfunction "}}}
function! eskk#_cmd_eskk_map(args) "{{{
    let [options, type, args] = s:parse_options(a:args)

    let args = s:skip_white(args)
    let [lhs, args] = s:parse_one_arg_from_q_args(args)

    let args = s:skip_white(args)
    if args == ''
        call s:create_map(eskk#get_current_instance(), type, options, lhs, '', 'EskkMap')
        return
    endif

    call s:create_map(eskk#get_current_instance(), type, options, lhs, args, 'EskkMap')
endfunction "}}}


" Manipulate eskk instances.
function! eskk#get_current_instance() "{{{
    return s:eskk_instances[s:instance_id]
endfunction "}}}
function! eskk#create_new_instance() "{{{
    " TODO: CoW

    " Create instance.
    let inst = s:eskk_new()
    call add(s:eskk_instances, inst)
    let s:instance_id += 1

    " Initialize instance.
    call inst.enable(0)

    return inst
endfunction "}}}
function! eskk#destroy_current_instance() "{{{
    if s:instance_id == 0
        throw eskk#internal_error(['eskk'], "No more instances.")
    endif

    call remove(s:eskk_instances, s:instance_id)
    let s:instance_id -= 1
endfunction "}}}
function! eskk#get_mutable_stash(namespace) "{{{
    let obj = deepcopy(s:mutable_stash, 1)
    let obj.namespace = join(a:namespace, '-')
    return obj
endfunction "}}}

" s:mutable_stash "{{{
let s:mutable_stash = {}

" NOTE: Constructor is eskk#get_mutable_stash().

" This a:value will be set when new eskk instances are created.
function! s:mutable_stash.init(varname, value) dict "{{{
    call eskk#util#logf("s:mutable_stash - Initialize %s with %s.", a:varname, string(a:value))

    if !has_key(s:stash_prototype, self.namespace)
        let s:stash_prototype[self.namespace] = {}
    endif

    if !has_key(s:stash_prototype[self.namespace], a:varname)
        let s:stash_prototype[self.namespace][a:varname] = a:value
    else
        throw eskk#internal_error(['eskk'])
    endif
endfunction "}}}

function! s:mutable_stash.get(varname) dict "{{{
    call eskk#util#logf("s:mutable_stash - Get %s.", a:varname)

    let inst = eskk#get_current_instance()
    if !has_key(inst.stash, self.namespace)
        let inst.stash[self.namespace] = {}
    endif

    if has_key(inst.stash[self.namespace], a:varname)
        return inst.stash[self.namespace][a:varname]
    else
        " Find prototype for this variable.
        " These prototypes are set by `s:mutable_stash.init()`.
        if !has_key(s:stash_prototype, self.namespace)
            let s:stash_prototype[self.namespace] = {}
        endif

        if has_key(s:stash_prototype[self.namespace], a:varname)
            return s:stash_prototype[self.namespace][a:varname]
        else
            " No more stash.
            throw eskk#internal_error(['eskk'])
        endif
    endif
endfunction "}}}

function! s:mutable_stash.set(varname, value) dict "{{{
    call eskk#util#logf("s:mutable_stash - Set %s '%s'.", a:varname, string(a:value))

    let inst = eskk#get_current_instance()
    if !has_key(inst.stash, self.namespace)
        let inst.stash[self.namespace] = {}
    endif

    let inst.stash[self.namespace][a:varname] = a:value
endfunction "}}}

lockvar s:mutable_stash
" }}}


" Stubs for current eskk instance. {{{

" Enable/Disable IM
function! eskk#is_enabled() "{{{
    let self = eskk#get_current_instance()
    return call(self.is_enabled, [], self)
endfunction "}}}
function! eskk#enable() "{{{
    let self = eskk#get_current_instance()
    return call(self.enable, [], self)
endfunction "}}}
function! eskk#disable() "{{{
    let self = eskk#get_current_instance()
    return call(self.disable, [], self)
endfunction "}}}
function! eskk#toggle() "{{{
    let self = eskk#get_current_instance()
    return call(self.toggle, [], self)
endfunction "}}}

function! eskk#is_special_lhs(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.is_special_lhs, a:000, self)
endfunction "}}}
function! eskk#get_special_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_special_key, a:000, self)
endfunction "}}}

" Manipulate display string.
function! eskk#remove_display_str(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.remove_display_str, a:000, self)
endfunction "}}}
function! eskk#kakutei_str(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.kakutei_str, a:000, self)
endfunction "}}}

" Sticky key
function! eskk#get_sticky_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_sticky_key, a:000, self)
endfunction "}}}
function! eskk#get_sticky_char(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_sticky_char, a:000, self)
endfunction "}}}
function! eskk#is_sticky_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.is_sticky_key, a:000, self)
endfunction "}}}
function! eskk#sticky_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.sticky_key, a:000, self)
endfunction "}}}

" Henkan key
function! eskk#get_henkan_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_henkan_key, a:000, self)
endfunction "}}}
function! eskk#get_henkan_char(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_henkan_char, a:000, self)
endfunction "}}}
function! eskk#is_henkan_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.is_henkan_key, a:000, self)
endfunction "}}}

" Big letter keys
function! eskk#is_big_letter(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.is_big_letter, a:000, self)
endfunction "}}}

" Escape key
function! eskk#escape_key(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.escape_key, a:000, self)
endfunction "}}}

" Mode
function! eskk#set_mode(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.set_mode, a:000, self)
endfunction "}}}
function! eskk#get_mode(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_mode, a:000, self)
endfunction "}}}
function! eskk#is_supported_mode(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.is_supported_mode, a:000, self)
endfunction "}}}
function! eskk#register_mode(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.register_mode, a:000, self)
endfunction "}}}
function! eskk#validate_mode_structure(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.validate_mode_structure, a:000, self)
endfunction "}}}
function! eskk#get_mode_structure(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_mode_structure, a:000, self)
endfunction "}}}

" Statusline
function! eskk#get_stl(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_stl, a:000, self)
endfunction "}}}

" Buftable
function! eskk#get_buftable(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.get_buftable, a:000, self)
endfunction "}}}
function! eskk#set_buftable(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.set_buftable, a:000, self)
endfunction "}}}
function! eskk#rewrite(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.rewrite, a:000, self)
endfunction "}}}

" Event
function! eskk#register_event(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.register_event, a:000, self)
endfunction "}}}
function! eskk#register_temp_event(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.register_temp_event, a:000, self)
endfunction "}}}
function! eskk#throw_event(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.throw_event, a:000, self)
endfunction "}}}

" Locking diff old string
function! eskk#lock_old_str(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.lock_old_str, a:000, self)
endfunction "}}}
function! eskk#unlock_old_str(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.unlock_old_str, a:000, self)
endfunction "}}}

" Dispatch functions
function! eskk#filter(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.filter, a:000, self)
endfunction "}}}
function! eskk#call_via_filter(...) "{{{
    let self = eskk#get_current_instance()
    return call(self.call_via_filter, a:000, self)
endfunction "}}}

" }}}

" }}}

" Exceptions {{{
function! s:build_error(from, msg) "{{{
    return join(a:from, ': ') . ' - ' . join(a:msg, ': ')
endfunction "}}}
function! eskk#get_exception_message(error_str) "{{{
    " Get only `a:msg` of s:build_error().
    let s = a:error_str
    let s = substitute(s, '^.\{-} - ', '', '')
    return s
endfunction "}}}

function! eskk#internal_error(from, ...) "{{{
    return s:build_error(a:from, ['internal error'] + a:000)
endfunction "}}}
function! eskk#dictionary_look_up_error(from, ...) "{{{
    return s:build_error(a:from, ['dictionary look up error'] + a:000)
endfunction "}}}
function! eskk#out_of_idx_error(from, ...) "{{{
    return s:build_error(a:from, ['out of index'] + a:000)
endfunction "}}}
function! eskk#parse_error(from, ...) "{{{
    return s:build_error(a:from, ['parse error'] + a:000)
endfunction "}}}
function! eskk#assertion_failure_error(from, ...) "{{{
    " This is only used from eskk#util#assert().
    return s:build_error(a:from, ['assertion failed'] + a:000)
endfunction "}}}
function! eskk#user_error(from, msg) "{{{
    " Return simple message.
    " TODO Omit a:from to simplify message?
    return printf('%s: %s', join(a:from, ': '), a:msg)
endfunction "}}}
" }}}

" Write timestamp to debug file {{{
if g:eskk_debug && exists('g:eskk_debug_file') && filereadable(expand(g:eskk_debug_file))
    call writefile(['', printf('--- %s ---', strftime('%c')), ''], expand(g:eskk_debug_file))
endif
" }}}
" Egg-like-newline {{{
if !g:eskk_egg_like_newline
    function! s:register_egg_like_newline_event()
        let self = eskk#get_current_instance()

        " Default behavior is `egg like newline`.
        " Turns it to `Non egg like newline` during henkan phase.
        call self.register_event(['enter-phase-henkan', 'enter-phase-okuri', 'enter-phase-henkan-select'], 'eskk#mode#builtin#do_lmap_non_egg_like_newline', [1])
        call self.register_event('enter-phase-normal', 'eskk#mode#builtin#do_lmap_non_egg_like_newline', [0])
    endfunction
    autocmd VimEnter * call s:register_egg_like_newline_event()
endif
" }}}
" InsertLeave {{{
function! s:autocmd_insert_leave() "{{{
    let self = eskk#get_current_instance()
    call self.buftable.reset()

    if !g:eskk_keep_state && self.is_enabled()
        let disable = self.disable()
        noautocmd execute 'normal! i' . disable
    endif
endfunction "}}}
autocmd InsertLeave * call s:autocmd_insert_leave()
" }}}
" Default mappings - :EskkMap {{{
function! s:do_default_mappings() "{{{
    EskkMap -type=sticky -unique ;
    EskkMap -type=henkan -unique <Space>
    EskkMap -type=escape -unique <Esc>

    EskkMap -type=henkan-select:choose-next -unique <Space>
    EskkMap -type=henkan-select:choose-prev -unique x

    EskkMap -type=henkan-select:next-page -unique <Space>
    EskkMap -type=henkan-select:prev-page -unique x

    EskkMap -type=mode:hira:toggle-hankata -unique <C-q>
    EskkMap -type=mode:hira:ctrl-q-key -unique <C-q>
    EskkMap -type=mode:hira:toggle-kata -unique q
    EskkMap -type=mode:hira:q-key -unique q
    EskkMap -type=mode:hira:to-ascii -unique l
    EskkMap -type=mode:hira:to-zenei -unique L

    EskkMap -type=mode:kata:toggle-hankata -unique <C-q>
    EskkMap -type=mode:kata:ctrl-q-key -unique <C-q>
    EskkMap -type=mode:kata:toggle-kata -unique q
    EskkMap -type=mode:kata:q-key -unique q
    EskkMap -type=mode:kata:to-ascii -unique l
    EskkMap -type=mode:kata:to-zenei -unique L

    EskkMap -type=mode:hankata:toggle-hankata -unique <C-q>
    EskkMap -type=mode:hankata:ctrl-q-key -unique <C-q>
    EskkMap -type=mode:hankata:toggle-kata -unique q
    EskkMap -type=mode:hankata:q-key -unique q
    EskkMap -type=mode:hankata:to-ascii -unique l
    EskkMap -type=mode:hankata:to-zenei -unique L

    EskkMap -type=mode:ascii:to-hira -unique <C-j>

    EskkMap -type=mode:zenei:to-hira -unique <C-j>
endfunction "}}}
autocmd VimEnter * call s:do_default_mappings()
" }}}
" Map temporary key to keys to use in that mode {{{
function! eskk#map_mode_local_keys() "{{{
    let mode = eskk#get_mode()
    let keys = {
    \   'hira': [
    \       'henkan-select:choose-next',
    \       'henkan-select:choose-prev',
    \       'henkan-select:next-page',
    \       'henkan-select:prev-page',
    \       'mode:hira:q-key',
    \       'mode:hira:to-ascii',
    \       'mode:hira:to-zenei',
    \   ],
    \   'kata': [
    \       'henkan-select:choose-next',
    \       'henkan-select:choose-prev',
    \       'henkan-select:next-page',
    \       'henkan-select:prev-page',
    \       'mode:kata:q-key',
    \       'mode:kata:to-ascii',
    \       'mode:kata:to-zenei',
    \   ],
    \   'ascii': [
    \       'mode:ascii:to-hira',
    \   ],
    \   'zenei': [
    \       'mode:zenei:to-hira',
    \   ],
    \}

    if has_key(keys, mode)
        for key in keys[mode]
            let real_key = eskk#get_special_key(key)
            call eskk#set_up_temp_key(real_key)
            call eskk#register_temp_event('leave-mode-' . mode, 'eskk#set_up_temp_key_restore', [real_key])
        endfor
    endif
endfunction "}}}
call eskk#register_event(['enter-mode-hira', 'enter-mode-kata', 'enter-mode-ascii', 'enter-mode-zenei'], 'eskk#map_mode_local_keys', [])
" }}}
" Save dictionary if modified {{{
if g:eskk_auto_save_dictionary_at_exit
    autocmd VimLeavePre * call eskk#mode#builtin#update_dictionary()
endif
" }}}

augroup END

" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
