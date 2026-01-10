require "../spec_helper"

describe CrymbleUI::Scheduler do
    describe "timer scheduling" do
        it "schedules a one-shot timer" do
            scheduler = CrymbleUI::Scheduler.new
            fired = false

            timer_id = scheduler.schedule(10.milliseconds) {
                fired = true
            }

            timer_id.should be >= 0
            fired.should be_false # Not fired yet
        end

        it "schedules a repeating timer" do
            scheduler = CrymbleUI::Scheduler.new
            fired = false

            timer_id = scheduler.schedule(10.milliseconds, repeating: true) {
                fired = true
            }

            timer_id.should be >= 0
            fired.should be_false # Not fired yet
        end

        it "returns unique timer IDs" do
            scheduler = CrymbleUI::Scheduler.new
            id1 = scheduler.schedule(10.milliseconds) { }
            id2 = scheduler.schedule(10.milliseconds) { }

            id1.should_not eq(id2)
        end
    end

    describe "next_wake_time" do
        it "returns nil when no timers scheduled" do
            scheduler = CrymbleUI::Scheduler.new
            scheduler.next_wake_time.should be_nil
        end

        it "returns time until next timer" do
            scheduler = CrymbleUI::Scheduler.new
            scheduler.schedule(100.milliseconds) { }

            next_wake = scheduler.next_wake_time
            next_wake.should_not be_nil
            next_wake.not_nil!.should be > Time::Span.zero
            next_wake.not_nil!.should be <= 100.milliseconds
        end

        it "returns soonest timer when multiple scheduled" do
            scheduler = CrymbleUI::Scheduler.new
            scheduler.schedule(100.milliseconds) { }
            scheduler.schedule(50.milliseconds) { }
            scheduler.schedule(150.milliseconds) { }

            next_wake = scheduler.next_wake_time
            next_wake.should_not be_nil
            # Should be time until the 50ms timer
            next_wake.not_nil!.should be <= 50.milliseconds
        end
    end

    describe "run_expired_timers" do
        it "fires timer after delay" do
            scheduler = CrymbleUI::Scheduler.new
            fired = false

            scheduler.schedule(10.milliseconds) {
                fired = true
            }

            # Wait for timer to expire
            sleep(15.milliseconds)

            count = scheduler.run_expired_timers
            count.should eq(1)
            fired.should be_true
        end

        it "does not fire timer before delay" do
            scheduler = CrymbleUI::Scheduler.new
            fired = false

            scheduler.schedule(50.milliseconds) {
                fired = true
            }

            # Check immediately
            count = scheduler.run_expired_timers
            count.should eq(0)
            fired.should be_false
        end

        it "fires multiple expired timers" do
            scheduler = CrymbleUI::Scheduler.new
            count1 = 0
            count2 = 0

            scheduler.schedule(10.milliseconds) { count1 += 1 }
            scheduler.schedule(15.milliseconds) { count2 += 1 }

            sleep(20.milliseconds)

            fired = scheduler.run_expired_timers
            fired.should eq(2)
            count1.should eq(1)
            count2.should eq(1)
        end

        it "repeating timer fires multiple times" do
            scheduler = CrymbleUI::Scheduler.new
            fire_count = 0

            scheduler.schedule(20.milliseconds, repeating: true) {
                fire_count += 1
            }

            # Wait for ~3 cycles
            sleep(70.milliseconds)

            # Fire all expired
            scheduler.run_expired_timers
            first_count = fire_count

            # Wait for another cycle
            sleep(25.milliseconds)
            scheduler.run_expired_timers

            fire_count.should be > first_count
        end

        it "one-shot timer fires only once" do
            scheduler = CrymbleUI::Scheduler.new
            fire_count = 0

            scheduler.schedule(10.milliseconds) {
                fire_count += 1
            }

            sleep(15.milliseconds)
            scheduler.run_expired_timers
            first_count = fire_count

            sleep(15.milliseconds)
            scheduler.run_expired_timers

            # Should not fire again
            fire_count.should eq(first_count)
        end
    end

    describe "cancel" do
        it "prevents timer from firing" do
            scheduler = CrymbleUI::Scheduler.new
            fired = false

            timer_id = scheduler.schedule(10.milliseconds) {
                fired = true
            }

            scheduler.cancel(timer_id)
            sleep(15.milliseconds)
            scheduler.run_expired_timers

            fired.should be_false
        end

        it "stops repeating timer" do
            scheduler = CrymbleUI::Scheduler.new
            fire_count = 0

            timer_id = scheduler.schedule(10.milliseconds, repeating: true) {
                fire_count += 1
            }

            # Fire once
            sleep(15.milliseconds)
            scheduler.run_expired_timers
            first_count = fire_count

            # Cancel and wait
            scheduler.cancel(timer_id)
            sleep(20.milliseconds)
            scheduler.run_expired_timers

            # Should not fire again
            fire_count.should eq(first_count)
        end

        it "does nothing for invalid timer ID" do
            scheduler = CrymbleUI::Scheduler.new
            # Should not crash
            scheduler.cancel(9999)
        end
    end
end
