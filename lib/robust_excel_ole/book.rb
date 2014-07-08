# -*- coding: utf-8 -*-

class Hash
  def first
    to_a.first
  end
end


module RobustExcelOle

  class Book
    attr_reader :book

    class << self
      def open(file, options={ }, &block)
        new(file, options, &block)
      end
    end

    def initialize(file, options={ }, &block)
      unless caller[1] =~ /book.rb:\d+:in\s+`open'$/
        warn "DEPRECATION WARNING: RobustExcelOle::Book.new and RobustExcelOle::Book.open will be split. If you open existing file, please use RobustExcelOle::Book.open.(call from #{caller[1]})"
      end

      @options = {
        :read_only => true,
        :displayalerts => false,
        :visible => false
      }.merge(options)
      @winapp = WIN32OLE.new('Excel.Application')
      @winapp.DisplayAlerts = @options[:displayalerts]
      @winapp.Visible = @options[:visible]
      WIN32OLE.const_load(@winapp, RobustExcelOle) unless RobustExcelOle.const_defined?(:CONSTANTS)
      @book = @winapp.Workbooks.Open(absolute_path(file),{ 'ReadOnly' => @options[:read_only] })

      if block
        begin
          yield self
        ensure
          close
        end
      end

      @book
    end

    def close
      @winapp.Workbooks.Close
      @winapp.Quit
    end

    def save(file = nil, opts = {:if_exists => :raise} )
      raise IOError, "Not opened for writing(open with :read_only option)" if @options[:read_only]
      return @book.save unless file

      dirname, basename = File.split(file)
      #puts "basename: #{basename}"
      extname = File.extname(basename)
      basename = File.basename(basename)
      #puts "basename: #{basename}"
      case extname
      when '.xls'
        file_format = RobustExcelOle::XlExcel8
      when '.xlsx'
        file_format = RobustExcelOle::XlOpenXMLWorkbook
      when '.xlsm'
        file_format = RobustExcelOle::XlOpenXMLWorkbookMacroEnabled
      end
      #puts "file: #{file}"
      #puts "dirname: #{dirname}"
      #puts "extname: #{extname}"
      #puts "absolute: #{absolute_path(File.join(dirname, basename))}"
      #puts "absolute: #{absolute_path(file)}"
      if File.exist?(file) then
        case opts[:if_exists]
        when :overwrite 
          File.delete(absolute_path(File.join(dirname, basename)))
          #File.delete(file)
        when :excel 
          raise ExcelErrorSave, "Option nicht implementiert"
        when :raise
          raise ExcelErrorSave, "Mappe existiert bereits: #{basename}"
        else
          raise ExcelErrorSave, "Bug: Ungültige Option (#{opts[:if_exists]})"
        end
      end
      #@book.SaveAs(file, file_format) 
      @book.SaveAs(absolute_path(File.join(dirname, basename)), file_format) 
    end

    def [] sheet
      sheet += 1 if sheet.is_a? Numeric
      RobustExcelOle::Sheet.new(@book.Worksheets.Item(sheet))
    end

    def each
      @book.Worksheets.each do |sheet|
        yield RobustExcelOle::Sheet.new(sheet)
      end
    end

    def add_sheet(sheet = nil, options = { })
      if sheet.is_a? Hash
        options = sheet
        sheet = nil
      end

      new_sheet_name = options.delete(:as)

      after_or_before, base_sheet = options.first || [:after, RobustExcelOle::Sheet.new(@book.Worksheets.Item(@book.Worksheets.Count))]
      base_sheet = base_sheet.sheet
      sheet ? sheet.Copy({ after_or_before.to_s => base_sheet }) : @book.WorkSheets.Add({ after_or_before.to_s => base_sheet })

      new_sheet = RobustExcelOle::Sheet.new(@winapp.Activesheet)
      new_sheet.name = new_sheet_name if new_sheet_name
      new_sheet
    end        

    private
    def absolute_path(file)
      file = File.expand_path(file)
      file = RobustExcelOle::Cygwin.cygpath('-w', file) if RUBY_PLATFORM =~ /cygwin/
      WIN32OLE.new('Scripting.FileSystemObject').GetAbsolutePathName(file)
    end
  end

end

class ExcelErrorSave < RuntimeError
end

