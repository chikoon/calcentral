require "spec_helper"

describe "MyAcademics::Semesters", :if => Sakai::SakaiData.test_data? do
  subject { MyAcademics::Semesters.new("300939").merge(@feed ||= {}); @feed[:semesters] }

  context "should get properly formatted data from fake Oracle MV" do
    it { subject.length.should eq(4) }
    it { subject[0][:name].should eq "Summer 2014" }
    it { subject[0][:termCode].should eq "C" }
    it { subject[0][:termYear].should eq "2014" }
    it { subject[0][:timeBucket].should eq 'future'}
    it { subject[0][:classes].length.should eq 1 }
    it { subject[0][:classes][0][:course_code].should eq "BIOLOGY 1A" }
    it { subject[0][:classes][0][:dept].should eq "BIOLOGY" }
    it { subject[0][:classes][0][:sections].length.should eq 1 }
    it { subject[0][:classes][0][:sections][0][:ccn].should eq "07309" }
    it { subject[0][:classes][0][:sections][0][:waitlistPosition].should eq 42 }
    it { subject[0][:classes][0][:sections][0][:enroll_limit].should eq 5000 }
    it { subject[0][:classes][0][:sections][0][:grade_option].should eq "P/NP" }
    it { subject[0][:classes][0][:url].should eq '/academics/semester/summer-2014/class/biology-1a' }
    it { subject[1][:name].should eq "Spring 2014" }
    it { subject[1][:timeBucket].should eq 'future'}
    it { subject[2][:name].should eq "Fall 2013"}
    it { subject[2][:timeBucket].should eq 'current' }
    it { subject[3][:name].should eq "Spring 2012" }
    it { subject[3][:timeBucket].should eq 'past' }
    it { subject[2][:classes].length.should eq 2 }
    it { subject[2][:classes][0][:course_code].should eq "BIOLOGY 1A" }
    it { subject[2][:classes][0][:dept].should eq "BIOLOGY" }
    it { subject[2][:classes][0][:sections].length.should eq 2 }
    it { subject[2][:classes][0][:sections][0][:ccn].should eq "07309" }
    it { subject[2][:classes][0][:sections][0][:schedules][0][:schedule].should eq "M 4:00P-5:00P" }
    it { subject[2][:classes][0][:slug].should eq "biology-1a" }
    it { subject[2][:classes][0][:title].should eq "General Biology Lecture" }
    it { subject[2][:classes][0][:url].should eq '/academics/semester/fall-2013/class/biology-1a' }
    it { subject[2][:classes][0][:sections][0][:grade_option].should eq "Letter" }
    it { subject[2][:classes][0][:sections][0][:instruction_format].should eq "LEC" }
    it { subject[2][:classes][0][:sections][0][:section_number].should eq "003" }
    it { subject[2][:classes][0][:sections][0][:section_label].should eq "LEC 003" }
    it { subject[2][:classes][0][:sections][0][:instructors][0][:name].present?.should be_true }
    it { subject[2][:classes][0][:sections][0][:is_primary_section].should be_true }
    it { subject[2][:classes][0][:sections][0][:units].to_s.should eq "5.0" }
    it { subject[3][:classes][0][:transcript][0][:grade].should eq "B" }
    it { subject[3][:classes][0][:transcript][0][:units].to_s.should eq "4.0" }
    it { subject[3][:classes][1][:transcript][0][:grade].should eq "C+" }
    it { subject[3][:classes][1][:transcript][0][:units].to_s.should eq "3.0" }
  end

  context "should be able to constrain semester range" do
    before {Settings.terms.stub(:oldest).and_return('fall-2013')}
    its(:length) {should eq 3}
  end

end
