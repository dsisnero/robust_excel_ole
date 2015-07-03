# example_expanding.rb:  
# create a workbook which is named like the old one, expect that the suffix "_expanded" is appended to the base name
# for each (global or local) Excel name of the workbook that refers to a range in a single sheet
# this sheet is to be copied into the new workbook
# the sheet's name shall be the name of the Excel name
# in addition to that, the cell B2 shall be named "name" and get the sheet name as its value 

require 'rubygems'
require 'robust_excel_ole'
require "fileutils"

include RobustExcelOle

begin
  Excel.close_all
  dir = "C:/data"
  workbook_name = 'workbook_named_concat.xls'
  base_name = workbook_name[0,workbook_name.rindex('.')]
  suffix = workbook_name[workbook_name.rindex('.')+1,workbook_name.length]
  file_name = dir + "/" + workbook_name
  extended_file_name = dir + "/" + base_name + "_expanded" + "." + suffix
  book_orig = Book.open(file_name)
  book_orig.save_as(extended_file_name, :if_exists => :overwrite) 
  book_orig.close
  sheet_names = []
  Book.unobtrusively(extended_file_name) do |book|     
    book.each do |sheet|
      sheet_names << sheet.name
    end
    book.Names.each do |excel_name|
      full_name = excel_name.Name
      sheet_name, short_name = full_name.split("!")
      sheet = excel_name.RefersToRange.Worksheet
      sheet_name = short_name ? short_name : full_name
      begin
        sheet_new = book.add_sheet(sheet, :as => sheet_name)
      rescue ExcelErrorSheet => msg
        if msg.message == "sheet name already exists" 
          sheet_new = book.add_sheet(sheet, :as => (sheet_name+sheet.name))
        else 
          puts msg.message
        end
      end
      sheet_new.Names.Add("Name" => "name", "RefersTo" => "=" + "$B$2")
      sheet_new[1,1].Value = sheet_name
      begin
        sheet_new.name = sheet_name
      rescue
        sheet_new.name = (sheet_name+sheet.name)
      end
    end
    sheet_names.each do |sheet_name|
      book[sheet_name].Delete()
    end
  end
  Excel.close_all
end