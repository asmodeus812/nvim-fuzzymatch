function! fuzzymatch#getbufinfo(bufnr) abort
  let info = getbufinfo(a:bufnr)
  if empty(info)
    return []
  endif
  let vars = info[0].variables
  unlet! info[0].variables
  if !empty(vars) && has_key(vars, "current_syntax")
    let info[0].variables = { "current_syntax": vars.current_syntax }
  endif
  unlet! vars
  return info[0]
endfunction

function! fuzzymatch#getwininfo(winid) abort
  let info = getwininfo(a:winid)
  if empty(info)
    return []
  endif
  unlet! info[0].variables
  return info[0]
endfunction
