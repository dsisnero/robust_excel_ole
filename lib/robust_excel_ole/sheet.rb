# -*- coding: utf-8 -*-
module RobustExcelOle
  class Sheet
    attr_reader :worksheet
    include Enumerable

    def initialize(win32_worksheet)
      @worksheet = win32_worksheet
      if @worksheet.ProtectContents
        @worksheet.Unprotect
        @end_row = last_row
        @end_column = last_column
        @worksheet.Protect
      else
        @end_row = last_row
        @end_column = last_column
      end
    end

    def name
      @worksheet.Name
    end

    def name= (new_name)
      begin
        @worksheet.Name = new_name
      rescue WIN32OLERuntimeError => msg
        if msg.message =~ /800A03EC/ 
          raise ExcelErrorSheet, "sheet name already exists"
        end
      end
    end

    # return the value of a cell, if row and column, or its name are given 
    def [] y, x = nil
      if x 
        yx = "#{y}_#{x}"
        @cells ||= { }
        @cells[yx] ||= RobustExcelOle::Cell.new(@worksheet.Cells.Item(y, x))
      else
        nvalue(y)
      end
    end

    # set the value of a cell, if row and column, or its name are given
    def []= (y, x, value = :__not_provided)
      if value != :__not_provided
        @worksheet.Cells.Item(y, x).Value = value
      else
        name, value = y, x
        set_nvalue(name, value)
      end
    end

    def each
      each_row do |row_range|
        row_range.each do |cell|
          yield cell
        end
      end
    end

    def each_row(offset = 0)
      offset += 1
      1.upto(@end_row) do |row|
        next if row < offset
        yield RobustExcelOle::Range.new(@worksheet.Range(@worksheet.Cells(row, 1), @worksheet.Cells(row, @end_column)))
      end
    end

    def each_row_with_index(offset = 0)
      each_row(offset) do |row_range|
        yield RobustExcelOle::Range.new(row_range), (row_range.row - 1 - offset)
      end
    end

    def each_column(offset = 0)
      offset += 1
      1.upto(@end_column) do |column|
        next if column < offset
        yield RobustExcelOle::Range.new(@worksheet.Range(@worksheet.Cells(1, column), @worksheet.Cells(@end_row, column)))
      end
    end

    def each_column_with_index(offset = 0)
      each_column(offset) do |column_range|
        yield RobustExcelOle::Range.new(column_range), (column_range.column - 1 - offset)
      end
    end

    def row_range(row, range = nil)
      range ||= 1..@end_column
      RobustExcelOle::Range.new(@worksheet.Range(@worksheet.Cells(row , range.min ), @worksheet.Cells(row , range.max )))
    end

    def col_range(col, range = nil)
      range ||= 1..@end_row
      RobustExcelOle::Range.new(@worksheet.Range(@worksheet.Cells(range.min , col ), @worksheet.Cells(range.max , col )))
    end

    # returns the contents of a range with given name
    # if no contents could returned, then return default value, if a default value was provided
    #                                raise an error, otherwise
    def nvalue(name, opts = {:default => nil})
      begin
        item = self.Names.Item(name)
      rescue WIN32OLERuntimeError
        return opts[:default] if opts[:default]
        raise SheetError, "name #{name} not in sheet"
      end
      begin
        value = item.RefersToRange.Value
      rescue  WIN32OLERuntimeError
        return opts[:default] if opts[:default]
        raise SheetError, "RefersToRange of name #{name}"
      end
      value
    end

    # returns the contents of a range with given name
    #def [] name
    #  nvalue(name)
    #end

    def set_nvalue(name,value)
      begin
        item = self.Names.Item(name)
      rescue WIN32OLERuntimeError
        raise SheetError, "name #{name} not in sheet"
      end
      begin
        item.RefersToRange.Value = value
      rescue  WIN32OLERuntimeError
        raise SheetError, "RefersToRange of name #{name}"
      end
    end

    # adds a name to a range given by an address
    # row, column are oriented at 0
    def add_name(row,column,name)
      begin
        old_name = self[row,column].Name.Name rescue nil
        if old_name
          self[row,column].Name.Name = name
        else
          address = "Z" + row.to_s + "S" + column.to_s 
          self.Names.Add("Name" => name, "RefersToR1C1" => "=" + address)
        end
      rescue WIN32OLERuntimeError => msg
        #puts "WIN32OLERuntimeError: #{msg.message}"
        raise SheetError, "cannot add name #{name} to cell with row #{row} and column #{column}"
      end
    end

    def method_missing(id, *args)  # :nodoc: #
      @worksheet.send(id, *args)
    end

    private
    def last_row
      special_last_row = @worksheet.UsedRange.SpecialCells(RobustExcelOle::XlLastCell).Row
      used_last_row = @worksheet.UsedRange.Rows.Count

      special_last_row >= used_last_row ? special_last_row : used_last_row
    end

    def last_column
      special_last_column = @worksheet.UsedRange.SpecialCells(RobustExcelOle::XlLastCell).Column
      used_last_column = @worksheet.UsedRange.Columns.Count

      special_last_column >= used_last_column ? special_last_column : used_last_column
    end    
  end

  public
  
  class SheetError < RuntimeError    # :nodoc: #
  end

end
