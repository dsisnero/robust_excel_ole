# example_copying.rb:
# each named cell is to be copied into another sheet
# unnamed cells shall not be copied
# if a sheet does not contain any named cell, then the sheet shall not be copied

require 'rubygems'
#require 'general'
require File.join(File.dirname(__FILE__), '../../lib/general')
require "fileutils"

include RobustExcelOle

begin
  dir = "C:/data"
  workbook_name = 'another_workbook.xls'
  ws = workbook_name.split(".")
  base_name = ws[0,ws.length-1].join(".")
  suffix = ws.last  
  file_name = dir + "/" + workbook_name
  extended_file_name = dir + "/" + base_name + "_copied" + "." + suffix
  FileUtils.copy file_name, extended_file_name 

  Book.unobtrusively(extended_file_name) do |book|  
    book.extend Enumerable
    sheet_names = book.map { |sheet| sheet.name }
    
    book.each do |sheet|
      new_sheet = book.add_sheet 
      contains_named_cells = false
      sheet.each do |cell|
        full_name = cell.Name.Name rescue nil
        if full_name
          sheet_name, short_name = full_name.split("!") 
          cell_name = short_name ? short_name : sheet_name
          contains_named_cells = true
          new_sheet[cell.Row, cell.Column].Value = cell.Value
          new_sheet.set_name(cell_name, cell.Row,cell.Column)
        end
      end
      new_sheet.Delete() unless contains_named_cells
    end
    
    sheet_names.each do |sheet_name|
      book.sheet(sheet_name).Delete()
    end
  end
end
