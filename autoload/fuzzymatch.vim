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
  unlet! raw_info.linecount
  unlet! raw_info.changedtick
  unlet! raw_info.lnum
  unlet! raw_info.lnumcur
  unlet! raw_info.lnumnum
  unlet! raw_info.lnumshown
  unlet! raw_info.lastusedtick
  unlet! info_list
  return info_list[0]
endfunction

function! fuzzymatch#getwininfo(winid) abort
  let info = getwininfo(a:winid)
  if empty(info)
    return []
  endif
  unlet! info[0].variables
  return info[0]
endfunction
