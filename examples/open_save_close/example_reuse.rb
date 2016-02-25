# example_reuse.rb: open a book in a new Excel and a running Excel instance. make visible

require File.join(File.dirname(__FILE__), '../../lib/general')
require File.join(File.dirname(__FILE__), '../../spec/helpers/create_temporary_dir')
require "fileutils"

include RobustExcelOle

Excel.close_all
begin
  dir = create_tmpdir
  file_name1 = dir + 'workbook.xls'
  file_name2 = dir + 'different_workbook.xls'
  file_name3 = dir + 'different_workbook.xls'
  file_name4 = dir + 'book_with_blank.xls'
  book1 = Book.open(file_name1)             # open a book in a new Excel instance since no Excel is open
  book1.excel.visible = true                # make current Excel visible
  sleep 2
  book2 = Book.open(file_name2)             # open a new book in the same Excel instance
  sleep 2                                   
  book3 = Book.open(file_name3, :force_excel => :new, :visible => true) # open another book in a new Excel instance, 
  sleep 2                                                          # make Excel visible
  book4 = Book.open(file_name4, :visible => true)  # open anther book, and use a running Excel application
  sleep 2                                          # (Excel chooses the first Excel application)        
  book1.close                               # close the books
  book2.close                                             
  book3.close
  book4.close                                         
ensure
  Excel.close_all                       # close all workbooks, quit Excel application
  rm_tmp(dir)
end


