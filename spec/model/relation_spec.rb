# encoding: utf-8
require File.join(File.dirname(__FILE__), "../spec_helper.rb")

describe Her::Model::Relation do
  describe :where do
    context "for base classes" do
      before do
        Her::API.setup :url => "https://api.example.com" do |builder|
          builder.use Her::Middleware::FirstLevelParseJSON
          builder.adapter :test do |stub|
            stub.get("/users?foo=1&bar=2") { |env| ok! [{ :id => 2, :fullname => "Tobias Fünke" }] }
            stub.get("/users?admin=1") { |env| ok! [{ :id => 1, :fullname => "Tobias Fünke" }] }

            stub.get("/users") do |env|
              ok! [
                { :id => 1, :fullname => "Tobias Fünke" },
                { :id => 2, :fullname => "Lindsay Fünke" },
                @created_user,
              ].compact
            end

            stub.post('/users') do |env|
              @created_user = { :id => 3, :fullname => 'George Michael Bluth' }
              ok! @created_user
            end
          end
        end

        spawn_model "Foo::User"
      end

      it "doesn't fetch the data immediatly" do
        expect(Foo::User).to receive(:request).never
        @users = Foo::User.where(:admin => 1)
      end

      it "fetches the data and passes query parameters" do
        expect(Foo::User).to receive(:request).once.and_call_original
        @users = Foo::User.where(:admin => 1)
        expect(@users).to respond_to(:length)
        expect(@users.size).to eql 1
      end

      it "chains multiple where statements" do
        @user = Foo::User.where(:foo => 1).where(:bar => 2).first
        expect(@user.id).to eq(2)
      end

      it "does not reuse relations" do
        expect(Foo::User.all.size).to eql 2
        expect(Foo::User.create(:fullname => 'George Michael Bluth').id).to eq(3)
        expect(Foo::User.all.size).to eql 3
      end
    end

    context "for parent class" do
      before do
        Her::API.setup :url => "https://api.example.com" do |builder|
          builder.use Her::Middleware::FirstLevelParseJSON
          builder.adapter :test do |stub|
            stub.get("/users?page=2") { |env| ok! [{ :id => 1, :fullname => "Tobias Fünke" }, { :id => 2, :fullname => "Lindsay Fünke" }] }
          end
        end

        spawn_model("Foo::Model") do
          scope :page, lambda { |page| where(:page => page) }
        end

        class User < Foo::Model; end
        @spawned_models << :User
      end

      it "propagates the scopes through its children" do
        @users = User.page(2)
        expect(@users.length).to eq(2)
      end
    end
  end

  describe :create do
    before do
      Her::API.setup :url => "https://api.example.com" do |builder|
        builder.use Her::Middleware::FirstLevelParseJSON
        builder.use Faraday::Request::UrlEncoded
        builder.adapter :test do |stub|
          stub.post("/users") { |env| ok! :id => 1, :fullname => params(env)[:fullname], :email => params(env)[:email] }
        end
      end

      spawn_model "Foo::User"
    end

    context "with a single where call" do
      it "creates a resource and passes the query parameters" do
        @user = Foo::User.where(:fullname => "Tobias Fünke", :email => "tobias@bluth.com").create
        expect(@user.id).to eq(1)
        expect(@user.fullname).to eq("Tobias Fünke")
        expect(@user.email).to eq("tobias@bluth.com")
      end
    end

    context "with multiple where calls" do
      it "creates a resource and passes the query parameters" do
        @user = Foo::User.where(:fullname => "Tobias Fünke").create(:email => "tobias@bluth.com")
        expect(@user.id).to eq(1)
        expect(@user.fullname).to eq("Tobias Fünke")
        expect(@user.email).to eq("tobias@bluth.com")
      end
    end
  end

  describe :build do
    before { spawn_model "Foo::User" }

    it "handles new resource with build" do
      @new_user = Foo::User.where(:fullname => "Tobias Fünke").build
      expect(@new_user.new?).to be_truthy
      expect(@new_user.fullname).to eq("Tobias Fünke")
    end
  end

  describe :scope do
    before do
      Her::API.setup :url => "https://api.example.com" do |builder|
        builder.use Her::Middleware::FirstLevelParseJSON
        builder.adapter :test do |stub|
          stub.get("/users?what=4&where=3") { |env| ok! [{ :id => 3, :fullname => "Maeby Fünke" }] }
          stub.get("/users?what=2") { |env| ok! [{ :id => 2, :fullname => "Lindsay Fünke" }] }
          stub.get("/users?where=6") { |env| ok! [{ :id => 4, :fullname => "Tobias Fünke" }] }
        end
      end

      spawn_model 'Foo::User' do
        scope :foo, lambda { |v| where(:what => v) }
        scope :bar, lambda { |v| where(:where => v) }
        scope :baz, lambda { bar(6) }
      end
    end

    it "passes query parameters" do
      @user = Foo::User.foo(2).first
      expect(@user.id).to eq(2)
    end

    it "passes multiple query parameters" do
      @user = Foo::User.foo(4).bar(3).first
      expect(@user.id).to eq(3)
    end

    it "handles embedded scopes" do
      @user = Foo::User.baz.first
      expect(@user.id).to eq(4)
    end
  end

  describe :default_scope do
    context "for new objects" do
      before do
        spawn_model 'Foo::User' do
          default_scope lambda { where(:active => true) }
          default_scope lambda { where(:admin => true) }
        end
      end

      it "should apply the scope to the attributes" do
        expect(Foo::User.new).to be_active
        expect(Foo::User.new).to be_admin
      end
    end

    context "for fetched resources" do
      before do
        Her::API.setup :url => "https://api.example.com" do |builder|
          builder.use Her::Middleware::FirstLevelParseJSON
          builder.use Faraday::Request::UrlEncoded
          builder.adapter :test do |stub|
            stub.post("/users") { |env| ok! :id => 3, :active => (params(env)[:active] == "true" ? true : false) }
          end
        end

        spawn_model 'Foo::User' do
          default_scope lambda { where(:active => true) }
        end
      end

      it("should apply the scope to the request") { expect(Foo::User.create).to be_active }
    end

    context "for fetched collections" do
      before do
        Her::API.setup :url => "https://api.example.com" do |builder|
          builder.use Her::Middleware::FirstLevelParseJSON
          builder.use Faraday::Request::UrlEncoded
          builder.adapter :test do |stub|
            stub.get("/users?active=true") { |env| ok! [{ :id => 3, :active => (params(env)[:active] == "true" ? true : false) }] }
          end
        end

        spawn_model 'Foo::User' do
          default_scope lambda { where(:active => true) }
        end
      end

      it("should apply the scope to the request") { expect(Foo::User.all.first).to be_active }
    end
  end

  describe :map do
    before do
      Her::API.setup :url => "https://api.example.com" do |builder|
        builder.use Her::Middleware::FirstLevelParseJSON
        builder.adapter :test do |stub|
          stub.get("/users") do |env|
            ok! [{ :id => 1, :fullname => "Tobias Fünke" }, { :id => 2, :fullname => "Lindsay Fünke" }]
          end
        end
      end

      spawn_model 'Foo::User'
    end

    it "delegates the method to the fetched collection" do
      expect(Foo::User.all.map(&:fullname)).to eq(["Tobias Fünke", "Lindsay Fünke"])
    end
  end
end
