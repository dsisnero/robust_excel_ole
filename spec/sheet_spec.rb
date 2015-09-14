# -*- coding: utf-8 -*-
require File.join(File.dirname(__FILE__), './spec_helper')

include RobustExcelOle

describe RobustExcelOle::Sheet do
  
  before do
    @dir = create_tmpdir
    @book = RobustExcelOle::Book.open(@dir + '/workbook.xls', :read_only => true)
    @sheet = @book[0]
  end

  after do
    @book.close
    rm_tmp(@dir)
  end

  before(:all) do
    Excel.close_all
  end 

  after(:all) do
    Excel.close_all
  end 

  describe ".initialize" do
    context "when open sheet protected(with password is 'protect')" do
      before do
        @key_sender = IO.popen  'ruby "' + File.join(File.dirname(__FILE__), '/helpers/key_sender.rb') + '" "Microsoft Office Excel" '  , "w"
        @key_sender.puts "{p}{r}{o}{t}{e}{c}{t}{enter}"
        @book_protect = RobustExcelOle::Book.open(@dir + '/protected_sheet.xls', :visible => true, :read_only => true)
        @protected_sheet = @book_protect['protect']
      end

      after do
        @book_protect.close
        @key_sender.close
      end

      it "should be a protected sheet" do
        @protected_sheet.ProtectContents.should be_true
      end

      it "protected sheet can't be write" do
        expect { @protected_sheet[1,1] = 'write' }.to raise_error
      end
    end

  end

  shared_context "sheet 'open book with blank'" do
    before do
      @book_with_blank = RobustExcelOle::Book.open(@dir + '/book_with_blank.xls', :read_only => true)
      @sheet_with_blank = @book_with_blank[0]
    end

    after do
      @book_with_blank.close
    end
  end

  describe "access sheet name" do
    describe "#name" do
      it 'get sheet1 name' do
        @sheet.name.should eq 'Sheet1'
      end
    end

    describe "#name=" do
      
      it 'change sheet1 name to foo' do
        @sheet.name = 'foo'
        @sheet.name.should eq 'foo'
      end

      it "should raise error when adding the same name" do
        @sheet.name = 'foo'
        @sheet.name.should eq 'foo'
        new_sheet = @book.add_sheet @sheet
        expect{
          new_sheet.name = 'foo'
        }.to raise_error(ExcelErrorSheet, /sheet name "foo" already exists/)
      end
    end
  end

  describe 'access cell' do

    describe "#[]" do      

      context "access [1,1]" do

        it { @sheet[1, 1].should be_kind_of RobustExcelOle::Cell }
        it { @sheet[1, 1].value.should eq 'foo' }
      end

      context "access [1, 1], [1, 2], [3, 1]" do
        it "should get every values" do
          @sheet[1, 1].value.should eq 'foo'
          @sheet[1, 2].value.should eq 'workbook'
          @sheet[3, 1].value.should eq 'matz'
        end
      end

      context "supplying nil as parameter" do
        it "should access [1,1]" do
          @sheet[1, nil].value.should eq 'foo'
          @sheet[nil, 1].value.should eq 'foo'
        end
      end

    end

    it "change a cell to 'bar'" do
      @sheet[1, 1] = 'bar'
      @sheet[1, 1].value.should eq 'bar'
    end

    it "should change a cell to nil" do
      @sheet[1, 1] = nil
      @sheet[1, 1].value.should eq nil
    end

    describe '#each' do
      it "should sort line in order of column" do
        @sheet.each_with_index do |cell, i|
          case i
          when 0
            cell.value.should eq 'foo'
          when 1
            cell.value.should eq 'workbook'
          when 2
            cell.value.should eq 'sheet1'
          when 3
            cell.value.should eq 'foo'
          when 4
            cell.value.should be_nil
          when 5
            cell.value.should eq 'foobaaa'
          end
        end
      end

      context "read sheet with blank" do
        include_context "sheet 'open book with blank'"

        it 'should get from ["A1"]' do
          @sheet_with_blank.each_with_index do |cell, i|
            case i
            when 5
              cell.value.should be_nil
            when 6
              cell.value.should eq 'simple'
            when 7
              cell.value.should be_nil
            when 8
              cell.value.should eq 'workbook'
            when 9
              cell.value.should eq 'sheet1'
            end
          end
        end
      end

    end

    describe "#each_row" do
      it "items should RobustExcelOle::Range" do
        @sheet.each_row do |rows|
          rows.should be_kind_of RobustExcelOle::Range
        end
      end

      context "with argument 1" do
        it 'should read from second row' do
          @sheet.each_row(1) do |rows|
            case rows.row
            when 2
              rows.values.should eq ['foo', nil, 'foobaaa']
            when 3
              rows.values.should eq ['matz', 'is', 'nice']
            end
          end
        end
      end

      context "read sheet with blank" do
        include_context "sheet 'open book with blank'"

        it 'should get from ["A1"]' do
          @sheet_with_blank.each_row do |rows|
            case rows.row - 1
            when 0
              rows.values.should eq [nil, nil, nil, nil, nil]
            when 1
              rows.values.should eq [nil, 'simple', nil, 'workbook', 'sheet1']
            when 2
              rows.values.should eq [nil, 'foo', nil, nil, 'foobaaa']
            when 3
              rows.values.should eq [nil, nil, nil, nil, nil]
            when 4
              rows.values.should eq [nil, 'matz', nil, 'is', 'nice']
            end
          end
        end
      end

    end

    describe "#each_row_with_index" do
      it "should read with index" do
        @sheet.each_row_with_index do |rows, idx|
          case idx
          when 0
            rows.values.should eq ['foo', 'workbook', 'sheet1']
          when 1
            rows.values.should eq ['foo', nil, 'foobaaa']
          when 2
            rows.values.should eq ['matz', 'is', 'nice']
          end
        end
      end

      context "with argument 1" do
        it "should read from second row, index is started 0" do
          @sheet.each_row_with_index(1) do |rows, idx|
            case idx
            when 0
              rows.values.should eq ['foo', nil, 'foobaaa']
            when 1
              rows.values.should eq ['matz', 'is', 'nice']
            end
          end
        end
      end

    end

    describe "#each_column" do
      it "items should RobustExcelOle::Range" do
        @sheet.each_column do |columns|
          columns.should be_kind_of RobustExcelOle::Range
        end
      end

      context "with argument 1" do
        it "should read from second column" do
          @sheet.each_column(1) do |columns|
            case columns.column
            when 2
              columns.values.should eq ['workbook', nil, 'is']
            when 3
              columns.values.should eq ['sheet1', 'foobaaa', 'nice']
            end
          end
        end
      end

      context "read sheet with blank" do
        include_context "sheet 'open book with blank'"

        it 'should get from ["A1"]' do
          @sheet_with_blank.each_column do |columns|
            case columns.column- 1
            when 0
              columns.values.should eq [nil, nil, nil, nil, nil]
            when 1
              columns.values.should eq [nil, 'simple', 'foo', nil, 'matz']
            when 2
              columns.values.should eq [nil, nil, nil, nil, nil]
            when 3
              columns.values.should eq [nil, 'workbook', nil, nil, 'is']
            when 4
              columns.values.should eq [nil, 'sheet1', 'foobaaa', nil, 'nice']
            end
          end
        end
      end

      context "read sheet which last cell is merged" do
        before do
          @book_merge_cells = RobustExcelOle::Book.open(@dir + '/merge_cells.xls')
          @sheet_merge_cell = @book_merge_cells[0]
        end

        after do
          @book_merge_cells.close
        end

        it "should get from ['A1'] to ['C2']" do
          columns_values = []
          @sheet_merge_cell.each_column do |columns|
            columns_values << columns.values
          end
          columns_values.should eq [
                                [nil, 'first merged', nil, 'merged'],
                                [nil, 'first merged', 'first', 'merged'],
                                [nil, 'first merged', 'second', 'merged'],
                                [nil, nil, 'third', 'merged']
                           ]
        end
      end
    end

    describe "#each_column_with_index" do
      it "should read with index" do
        @sheet.each_column_with_index do |columns, idx|
          case idx
          when 0
            columns.values.should eq ['foo', 'foo', 'matz']
          when 1
            columns.values.should eq ['workbook', nil, 'is']
          when 2
            columns.values.should eq ['sheet1', 'foobaaa', 'nice']
          end
        end
      end

      context "with argument 1" do
        it "should read from second column, index is started 0" do
          @sheet.each_column_with_index(1) do |column_range, idx|
            case idx
            when 0
              column_range.values.should eq ['workbook', nil, 'is']
            when 1
              column_range.values.should eq ['sheet1', 'foobaaa', 'nice']
            end
          end
        end
      end
    end

    describe "#row_range" do
      context "with second argument" do
        before do
          @row_range = @sheet.row_range(1, 2..3)
        end

        it { @row_range.should be_kind_of RobustExcelOle::Range }

        it "should get range cells of second argument" do
          @row_range.values.should eq ['workbook', 'sheet1']
        end
      end

      context "without second argument" do
        before do
          @row_range = @sheet.row_range(3)
        end

        it "should get all cells" do
          @row_range.values.should eq ['matz', 'is', 'nice']
        end
      end

    end

    describe "#col_range" do
      context "with second argument" do
        before do
          @col_range = @sheet.col_range(1, 2..3)
        end

        it { @col_range.should be_kind_of RobustExcelOle::Range }

        it "should get range cells of second argument" do
          @col_range.values.should eq ['foo', 'matz']
        end
      end

      context "without second argument" do
        before do
          @col_range = @sheet.col_range(2)
        end

        it "should get all cells" do
          @col_range.values.should eq ['workbook', nil, 'is']
        end
      end
    end

    describe "nvalue" do

      context "returning the value of a range" do
      
        before do
          @book1 = RobustExcelOle::Book.open(@dir + '/another_workbook.xls')
          @sheet1 = @book1[0]
        end

        after do
          @book1.close
        end   

        it "should return value of a range with nvalue and brackets operator" do
          @sheet1.nvalue("firstcell").should == "foo"
          @sheet1["firstcell"].should == "foo"
        end

        it "should raise an error if name not defined" do
          expect {
            value = @sheet1.nvalue("foo")
          }.to raise_error(SheetError, /cannot evaluate name "foo" in sheet/)
          expect {
            @sheet1["foo"]
          }.to raise_error(SheetError, /cannot evaluate name "foo" in sheet/)
        end

        it "should return default value if name not defined and default value is given" do
          @sheet1.nvalue("foo", :default => 2).should == 2
        end

        it "should evaluate a formula" do
          @sheet1.nvalue("named_formula").should == 4
        end
      end
    end

    describe "set_nvalue" do

      context "setting the value of a range" do
      
        before do
          @book1 = RobustExcelOle::Book.open(@dir + '/another_workbook.xls', :read_only => true)
          @sheet1 = @book1[0]
        end

        after do
          @book1.close
        end   

        it "should set a range to a value" do
          @sheet1.nvalue("firstcell").should == "foo"
          @sheet1[1,1].Value.should == "foo"
          @sheet1.set_nvalue("firstcell","foo")
          @sheet1.nvalue("firstcell").should == "foo"
          @sheet1[1,1].Value.should == "foo"
          @sheet1["firstcell"] = "bar"
          @sheet1.nvalue("firstcell").should == "bar"
          @sheet1[1,1].Value.should == "bar"
        end

        it "should raise an error" do
          expect{
            @sheet1.nvalue("foo")
            }.to raise_error(SheetError, /cannot evaluate name "foo" in sheet/)
        end
      end
    end

    describe "set_name" do

      context "setting the name of a range" do

         before do
          @book1 = RobustExcelOle::Book.open(@dir + '/another_workbook.xls', :read_only => true, :visible => true)
          @sheet1 = @book1[0]
        end

        after do
          @book1.close
        end   

        it "should name an unnamed range with a giving address" do
          expect{
            @sheet1[1,2].Name.Name
          }.to raise_error          
          @sheet1.set_name("foo",1,2)
          @sheet1[1,2].Name.Name.should == "Sheet1!foo"
        end

        it "should rename an already named range with a giving address" do
          @sheet1[1,1].Name.Name.should == "Sheet1!firstcell"
          @sheet1.set_name("foo",1,1)
          @sheet1[1,1].Name.Name.should == "Sheet1!foo"
        end

        it "should raise an error" do
          expect{
            @sheet1.set_name("foo",-2,1)
          }.to raise_error(SheetError, /cannot add name "foo" to cell with row -2 and column 1/)
        end
      end
    end

    describe "#method_missing" do
      it "can access COM method" do
        @sheet.Cells(1,1).Value.should eq 'foo'
      end

      context "unknown method" do
        it { expect { @sheet.hogehogefoo }.to raise_error }
      end
    end

  end
end
