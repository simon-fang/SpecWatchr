require "./watcher_dot_net.rb"

describe WatcherDotNet do
  before(:each) { $stdout.stub!(:puts) { } }
  describe "when initializing dot net watchr" do
    context "finding builder" do
      [
        { :builder => :MSBuilder },
        { :builder => :RakeBuilder }
      ].each do |kvp|
        it "should find #{kvp[:builder].to_s}" do
          @watcher = WatcherDotNet.new ".", 
            { :builder => kvp[:builder], :test_runner => :MSTestRunner }
          @watcher.builder.class.to_s.should == kvp[:builder].to_s
        end
      end
    end

    context "finding test runner" do
      before(:each) do
        mock = mock("Builder")
        mock.stub!(:new)
      end

      [
        { :test_runner => :MSTestRunner },
        { :test_runner => :NUnitRunner }
      ].each do |kvp|
        it "should find #{kvp[:test_runner].to_s}" do
          @watcher = 
            WatcherDotNet.new ".", { :builder => :MSBuilder, :test_runner => kvp[:test_runner] }

          @watcher.test_runner.class.to_s.should == kvp[:test_runner].to_s
        end
      end
    end
  end

  describe "when considering a file" do
    before(:each) do
      Find.stub!(:find).with(".").and_yield("sample.sln").and_yield("/bin/debug/sample.test.dll")

      @builder = mock("builder")
      MSBuilder.stub!(:new).and_return(@builder)
      @builder.stub!(:failed).and_return(true)

      @notifier = mock("notifier")
      GrowlNotifier.stub!(:new).and_return(@notifier)
      @notifier.stub!(:execute)

      @test_runner = mock("test_runner")
      MSTestRunner.stub!(:new).and_return(@test_runner)
      @test_runner.stub!(:inconclusive).and_return(false)
      @test_runner.stub!(:failed).and_return(false)

      @command_shell = mock("command_shell")
      CommandShell.stub!(:new).and_return(@command_shell)

      @spec_finder = mock("spec_finder")
      SpecFinder.stub!(:new).and_return(@spec_finder)
      @spec_finder.stub!(:find)

      @watcher = WatcherDotNet.new ".", { :builder => :MSBuilder, :test_runner => :MSTestRunner }
    end
    
    context "should not execute workflow if" do
      [
        { :name => 'SampleApp.Model.dll', :description => 'dll' }, 
        { :name => "SampleApp/bin/debug/", :description => 'debug directory' }, 
        { :name => 'TestResults.xml', :description => 'test xml file' }, 
        { :name => 'SampleApp/testresults', :description => 'test results directory' },
        { :name => 'dot_net_watcher.rb', :description => 'ruby file' }, 
        { :name => 'SampleApp.suo', :description => 'suo file' }
      ].each do |kvp|
        it "file changed is a #{kvp[:description]}" do
          @builder.should_not_receive(:execute)
          @watcher.consider "#{kvp[:name]}"
        end
      end
    end
    
    context "it is a valid file" do
      after(:each) { @watcher.consider "Person.cs" }

      it "should build" do
        @builder.should_receive(:execute) 
      end

      context "if the build fails" do
        before(:each) { given_build_fails }

        it "should notify the user" do
          @notifier.should_receive(:execute).with("build failed", "build output")
        end
      end

      context "if build succeeds" do
        before(:each) { given_build_succeeds }
        
        it "should find the spec" do
          @spec_finder.should_receive(:find).with("Person.cs")
        end
        
        context "if spec found" do
          before(:each) { @spec_finder.stub!(:find).with("Person.cs").and_return("PersonSpec") }

          it "should run tests" do
            @test_runner.should_receive(:execute).with("PersonSpec")
          end

          context "all tests passed" do
            before(:each) do
              @test_runner.should_receive(:execute).with("PersonSpec") do
                @test_runner.stub!(:inconclusive).and_return(false)
                @test_runner.stub!(:failed).and_return(false)
              end
            end

            it "should notify user that all tests passed" do
              @notifier.should_receive(:execute).with("all green", "all tests passed")
            end
          end

          context "no tests found for spec" do
            before(:each) do
              @test_runner.should_receive(:execute).with("PersonSpec") do
                @test_runner.stub!(:inconclusive).and_return(true)
                @test_runner.stub!(:failed).and_return(false)
                "no tests found"
              end
            end

            it "should notify user that tests wer inconclusive" do
              @notifier.should_receive(:execute).with("no spec found", "create spec PersonSpec")
            end
          end

          context "tests failed" do
            before(:each) do
              @test_runner.should_receive(:execute).with("PersonSpec") do
                @test_runner.stub!(:inconclusive).and_return(false)
                @test_runner.stub!(:failed).and_return(true)
                @test_runner.stub!(:test_results).and_return("3 tests failed")
              end
            end

            it "should notify user that tests failed" do
              @notifier.should_receive(:execute).with("tests failed", "3 tests failed")
            end
          end
        end
      end
    end

    def given_build_succeeds
       @builder.stub!(:execute) do
        @builder.stub!(:failed).and_return(false)
        "build output"
      end
    end

    def given_build_fails
       @builder.stub!(:execute) do
        @builder.stub!(:failed).and_return(true)
        "build output"
      end
    end
  end
end