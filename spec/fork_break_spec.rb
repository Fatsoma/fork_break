require 'spec_helper'
require 'tmpdir'

module ForkBreak
  describe Process do
    it "works as intented" do
      Dir.mktmpdir do |tmpdir|
        first_file = File.join(tmpdir, "first_file")
        second_file = File.join(tmpdir, "second_file")
        process = Process.new do |breakpoints|
          FileUtils.touch(first_file)
          breakpoints << :after_first_file
          FileUtils.touch(second_file)
        end
        File.exists?(first_file).should be_false
        File.exists?(second_file).should be_false
        
        process.run_until(:after_first_file).wait
        File.exists?(first_file).should be_true
        File.exists?(second_file).should be_false

        process.finish.wait
        File.exists?(first_file).should be_true
        File.exists?(second_file).should be_true
      end
    end
  
    it "raises an error (on wait) if a breakpoint is not encountered" do
      foo = Process.new do |breakpoints|
        if false
          breakpoints << :will_not_run
        end
      end
      expect do
        foo.run_until(:will_not_run).wait
      end.to raise_error(BreakpointNotReachedError)
    end

    it "works for the documentation example" do
      class FileCounter
        include ForkBreak::Breakpoints

        def self.open(path, use_lock = true)
          file = File.open(path, File::RDWR|File::CREAT, 0600)
          return new(file, use_lock)
        end

        def initialize(file, use_lock = true)
          @file = file
          @use_lock = use_lock
        end

        def increase
          breakpoints << :before_lock
          @file.flock(File::LOCK_EX) if @use_lock
          value = @file.read.to_i + 1
          breakpoints << :after_read
          @file.rewind
          @file.write("#{value}\n")
          @file.flush
          @file.truncate(@file.pos)
        end
      end

      def counter_after_synced_execution(counter_path, with_lock)
        process1, process2 = 2.times.map do
          ForkBreak::Process.new do
            FileCounter.open(counter_path, with_lock).increase
          end
        end

        process1.run_until(:after_read).wait

        # process2 can't wait for read since it will block
        process2.run_until(:before_lock).wait
        process2.run_until(:after_read) && sleep(0.1)

        process1.finish.wait # Finish process1
        process2.finish.wait # Finish process2

        File.read(counter_path).to_i
      end

      Dir.mktmpdir do |tmpdir|
        counter_path = File.join(tmpdir, "counter")

        counter_after_synced_execution(counter_path, with_lock = true).should == 2

        File.unlink(counter_path)
        counter_after_synced_execution(counter_path, with_lock = false).should == 1
      end
    end
  end
end