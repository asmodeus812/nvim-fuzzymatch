function! fuzzymatch#getbufinfo(bufnr) abort
  let info_list = getbufinfo(a:bufnr)
  if empty(info_list)
    return []
  endif
  let raw_info = info_list[0]
  let vars = raw_info.variables
  if !empty(vars) && has_key(vars, "current_syntax")
    let raw_info.variables = { "current_syntax": vars.current_syntax }
  else
    unlet! raw_info.variables
  endif
  unlet! vars
  unlet! raw_info.lnum
  unlet! raw_info.linecount
  unlet! raw_info.changedtick
  unlet! info_list
  return raw_info
endfunction

function! fuzzymatch#getwininfo(winid) abort
  let info = getwininfo(a:winid)
  if empty(info)
    return []
  endif
  unlet! info[0].variables
  return info[0]
endfunction

function! fuzzymatch#getregsig(regname) abort
  let info = getreginfo(a:regname)
  let contents = get(info, 'regcontents', [])
  let linecount = len(contents)
  let bytecount = 0
  for line in contents
    let bytecount += len(line)
  endfor
  let head = linecount > 0 ? strpart(contents[0], 0, 32) : ''
  let tail = linecount > 0 ? strpart(contents[-1], max([len(contents[-1]) - 32, 0]), 32) : ''
  return {
        \ 'name': a:regname,
        \ 'regtype': get(info, 'regtype', ''),
        \ 'linecount': linecount,
        \ 'bytecount': bytecount,
        \ 'head': head,
        \ 'tail': tail,
        \ }
endfunction

function! fuzzymatch#getmapsig(mode, buf) abort
  let maps = a:buf > 0 ? nvim_buf_get_keymap(a:buf, a:mode) : nvim_get_keymap(a:mode)
  let sigs = []
  for m in maps
    let rhs = get(m, 'rhs', '')
    call add(sigs, {
          \ 'lhs': get(m, 'lhs', ''),
          \ 'rhs_len': len(rhs),
          \ 'rhs_head': strpart(rhs, 0, 32),
          \ 'noremap': get(m, 'noremap', 0),
          \ 'expr': get(m, 'expr', 0),
          \ 'silent': get(m, 'silent', 0),
          \ })
  endfor
  return sigs
endfunction
