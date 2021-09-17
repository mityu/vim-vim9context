let s:CONTEXT_VIM_SCRIPT = 0
let s:CONTEXT_VIM9_SCRIPT = 1
let s:CONTEXT_UNKNOWN = 2

function! vim9context#is_vim9context() abort
  return vim9context#is_vim9context_pos(line('.'))
endfunction

function! vim9context#is_vim9context_pos(linenr) abort
  " First, check if there're modifiers that specify script type.
  let context = s:determine_context_by_line(a:linenr)
  if context != s:CONTEXT_UNKNOWN
    return context
  endif

  " Second, check if the line is in a function/vim9script-block.
  let context = s:determine_context_by_blocks(a:linenr)
  if context != s:CONTEXT_UNKNOWN
    return context
  endif

  " Finally, check if there's :vim9script command because when the line does
  " not meet the conditions above, the line is at script level.
  return s:determine_context_by_file()
endfunction


" Determine whether the given line is vim9script or not by checking
" command-modifiers.
function! s:determine_context_by_line(linenr) abort
  let components = split(getline(a:linenr))
  let context = s:CONTEXT_UNKNOWN
  for c in components
    if c =~# '^\<leg\%[acy]\>$'
      let context = s:CONTEXT_VIM_SCRIPT
    elseif c =~# '^\<vim9\%[cmd]\>$'
      let context = s:CONTEXT_VIM9_SCRIPT
    elseif c =~# '^\<fu\%[nction]\>'
      return s:CONTEXT_VIM_SCRIPT
    elseif c =~# '^\<def\>'
      return s:CONTEXT_VIM9_SCRIPT
    elseif c =~# '^\<export\>$'
      continue
    else
      break
    endif
  endfor
  return context
endfunction

function! s:determine_context_by_blocks(linenr) abort
  let curpos = getpos('.')
  try
    return s:determine_context_by_blocks_impl(a:linenr)
  finally
    call setpos('.', curpos)
  endtry
endfunction

function! s:determine_context_by_blocks_impl(linenr) abort
  execute printf('normal! %dG^', a:linenr)
  let innermost_def = s:find_innermost_def_function()

  " In def function, the context is always vim9script.
  if innermost_def != 0
    return s:CONTEXT_VIM9_SCRIPT
  endif

  " In legacy function, sometimes the context can be vim9script.
  let innermost_legacy = s:find_innermost_legacy_function()
  while 1
    let innermost_commandblock = s:find_innermost_braces_block()
    if innermost_commandblock == 0 || innermost_commandblock < innermost_legacy
      " Any functions can appear in vim9script block.
      break
    elseif s:is_vim9script_block(innermost_commandblock)
      return s:CONTEXT_VIM9_SCRIPT
    elseif innermost_commandblock == 1
      " There's no outer block anymore.
      break
    endif
    call cursor(innermost_commandblock - 1, 1)
  endwhile

  if innermost_legacy != 0
    return s:CONTEXT_VIM_SCRIPT
  endif
  return s:CONTEXT_UNKNOWN
endfunction

" Returns 1 when the given block is a vim9script block, such as below:
"   command! GreatCommand {
"     # Here is vim9script block
"   }
"   autocmd Event pattern {
"     # Here is vim9script block
"   }
"   (For details, see :h :command-repl)
" If the given block isn't a vim9script block, returns 0.
function! s:is_vim9script_block(linenr) abort
  let line = getline(a:linenr)
  if line =~# '\v^\s*%(com%[mand]>|au%[tocmd]>!@!).*\s\{\s*$'
    return 1
  endif
  return 0
endfunction

function! s:determine_context_by_file() abort
  let curpos = getpos('.')
  try
    normal! gg0
    let linenr = search('^\s*\<vim9s\%[cript]\>\s*$', 'cnW')
    if linenr <= 0
      return s:CONTEXT_VIM_SCRIPT
    endif
    return s:CONTEXT_VIM9_SCRIPT
  finally
    call setpos('.', curpos)
  endtry
endfunction

function! s:find_innermost_legacy_function() abort
  let begin = '\v^\s*%(<%(export|leg%[acy]|vim9%[cmd])>\s+)*fu%[nction]>'
  let end = 'en\%[dfunction]\>'
  return s:find_innermost_block(begin, end)
endfunction

function! s:find_innermost_def_function() abort
  let begin = '\v^\s*%(<%(export|legacy|vim9cmd)>\s+)*def>'
  let end = 'enddef\>'
  return s:find_innermost_block(begin, end)
endfunction

function! s:find_innermost_braces_block() abort
  let begin = '\s{\s*$'
  let end = '}'
  return s:find_innermost_block(begin, end)
endfunction

" Search the innermost block and returns the line that the block begins.
" If block is not found, returns 0.
function! s:find_innermost_block(begin, end) abort
  if getline('.') =~# a:begin
    return line('.')
  endif

  let linenr = searchpair(a:begin, '', a:end, 'bWnz')
  if linenr <= 0
    return 0
  endif
  return linenr
endfunction

" For testing
function! s:get_context_variables() abort
  return {
  \ 'vim_script': s:CONTEXT_VIM_SCRIPT,
  \ 'vim9_script': s:CONTEXT_VIM9_SCRIPT,
  \ 'unknown': s:CONTEXT_UNKNOWN,
  \ }
endfunction
