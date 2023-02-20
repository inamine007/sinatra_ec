require 'sinatra'
require 'sinatra/reloader'
require 'pg'
require 'dotenv'

set :environment, :production

# -----各種設定-----
configure do
  enable :sessions, :reloader
  Dotenv.load ".env"
end

client = PG::connect(
  # :host => "localhost",
  :user => ENV['DB_NAME'],
  :dbname => ENV['DB_USER'],
  :password => ENV['DB_PASS']
)

# -----定数-----
before do
  ADMIN_USER = ENV['ADMIN_USER']
  PAYMENT_METHOD = {
    'クレジット': '0',
    'paypay': '1',
    'コンビニ払い': '2',
    '代引き': '3'
  }
  PREFECTURES = {
    '北海道': '0',
    '東北': '1',
    '関東': '2',
    '中部': '3',
    '近畿': '4',
    '中国': '5',
    '四国': '6',
    '九州沖縄': '7',
  }
end

# 商品一覧
get '/' do
  @products = client.exec_params("SELECT * FROM products;").to_a
  return erb :index
end

# 商品詳細
get '/product/:id' do
  product_id = params[:id]
  @product = client.exec_params("SELECT * FROM products WHERE id = $1",
    [product_id]
  ).to_a.first
  @variation = client.exec_params("SELECT * FROM product_variation WHERE product_id = $1",
    [product_id]
  ).to_a
  return erb :product
end

# カート
get '/cart' do
  if !session[:cart].nil?
    ids = session[:cart]
    @cart = []
    ids.each do |id|
      tmp = client.exec_params(
        "SELECT pr.id, pr.name, pr.image, va.id, va.content, va.price
        FROM product_variation va
        LEFT JOIN products pr ON
        va.product_id = pr.id
        WHERE va.id = #{id}"
      ).to_a.first
      @cart.push(tmp)
    end
  end
  
  return erb :cart
end

post '/cart' do
  variation_id = params[:variation]
  if session[:cart].nil?
    session[:cart] = []
  end
  session[:cart].push(variation_id)
  return redirect '/cart'
end

# ログイン
get '/login' do
  unless session[:user].nil?
    return redirect '/'
  end

  return erb :login
end

post '/login' do
  email = params[:email]
  password = params[:password]
  # emailとpasswordに一致するユーザーを取得
  user = client.exec_params(
    "SELECT * FROM users WHERE email = $1 AND password = $2",
    [email, password]
  ).to_a.first
  # ユーザーが取得できなければログインページに、取得できればsessionにユーザー情報を格納してトップページに遷移
  if user.nil?
    return redirect '/login'
  else
    session[:user] = user
    return redirect '/'
  end
end

delete '/logout' do
  session[:user] = nil
  return redirect '/'
end

# 新規登録
get '/register' do
  unless session[:user].nil?
    return redirect '/'
  end
  @prefectures = PREFECTURES
  @payment_methods = PAYMENT_METHOD
  return erb :register
end

post '/register' do
  name = params[:name]
  zipcode = params[:zipcode]
  address1 = params[:address1]
  address2 = params[:address2]
  payment = params[:payment]
  email = params[:email]
  password = params[:password]

  begin
    # DBにユーザーを新規追加し、同時にreturningで結果を取得してログイン処理をする
    user = client.exec_params(
      "INSERT INTO users (name, zipcode, address1, address2, payment, email, password)
      VALUES ($1, $2, $3, $4, $5, $6, $7) returning *",
      [name, zipcode, address1, address2, payment, email, password]
    ).to_a.first

    session[:user] = user
    return redirect '/'
  rescue PG::UniqueViolation #例外処理 メールアドレスがかぶっている場合
    return redirect '/register'
  end
end

# カート内確認
get '/product_conf' do
  if !session[:cart].nil?
    ids = session[:cart]
    @cart = []
    ids.each do |id|
      tmp = client.exec_params(
        "SELECT pr.id, pr.name, pr.image, va.id, va.content, va.price
        FROM product_variation va
        LEFT JOIN products pr ON
        va.product_id = pr.id
        WHERE va.id = #{id}"
      ).to_a.first
      @cart.push(tmp)
    end
  end
  return erb :product_confirm
end

# ユーザー情報確認
get '/user_conf' do
  if !session[:user].nil?
    @user = session[:user]
  end
  p session[:user]
  @address = PREFECTURES.key(@user['address1'])
  @payment = PAYMENT_METHOD.key(@user['payment'])
  return erb :user_confirm
end

post '/complete' do
  if !session[:cart].nil?
    ids = session[:cart]
    ids_str = ids.join(',')
    total = client.exec_params(
      "SELECT sum(price)
      FROM product_variation
      WHERE id IN(#{ids_str})"
    ).to_a.first
    variation = client.exec_params("SELECT * FROM product_variation WHERE id IN(#{ids_str})").to_a
    user_id = session[:user]['id']
    begin
      # トランザクション開始
      client.exec("BEGIN")
      order = client.exec_params(
        "INSERT INTO orders (user_id, total, created_at) 
        VALUES (#{user_id}, #{total}, #{Time.now}) returning id"
      ).to_a.first

      variation.each do |var|
        price = var['price']
        
        client.exec_params(
          "INSERT INTO order_details (order_id, price)
          VALUES (#{order['id']}, #{price})"
        )
      end
      client.exec("COMMIT")
      return redirect "/"
    rescue
      # エラーがあれば処理を全てキャンセルする
      client.exec("ROLLBACK")
      return redirect "/cart"
    end
  end
  return redirect '/thanks'
end

# サンクス
get '/thanks' do
  return erb :thanks
end

#--- 管理画面↓ ---
# 商品登録
get '/admin/products/new' do
  return erb :'admin/product_new'
end

post '/products' do
  name = params[:name]
  description = params[:description]

  # 画像保存処理
  if !params[:img].nil? # 画像を受け取った場合
    image = params[:img][:filename]
    tempfile = params[:img][:tempfile] # デフォルトのファイル保存場所
    save_to = "./public/images/#{image}" # ファイルを保存したい場所
    FileUtils.mv(tempfile, save_to) # ファイルをデフォルトの場所から保存したい場所(public配下)に移動させる
  else
    # 画像を受け取らなかった場合、デフォルトの画像を設定する
    image = 'default.png'
  end

  # バリエーションを配列の形に加工する
  variation = [] # バリエーションを格納する空の配列を生成
  tmp = {} # 一時的にバリエーションを格納するハッシュを生成
  params.each do |key, value| # 受け取ったデータを1つ1つ見る
    split = key.split('_') # ['var', 'content', '0']みたいな形の配列になる
    if split[0] == 'var' # varという文字列を持っているデータの場合
      tmp[split[1]] = value # バリエーションのキーと値を一時ハッシュに追加
      if split[1] == 'price' # バリエーションのキーがpriceの場合
        variation.push(tmp) # 一時ハッシュを配列に入れる。[{'content': '3個入り', 'price': '120'}, {'content': '5個入り', 'price': '140'} ]みたいな配列ができる
        tmp = {} # 一時ハッシュをリセット
      end
    end
  end

  # 商品保存処理。productsテーブルの他に、product_variationテーブルにもデータを保存するのでトランザクションを使用する
  begin
    # トランザクション開始
    client.exec("BEGIN")
    # productsテーブルにデータを保存し、同時にidを取得
    product = client.exec_params(
      "INSERT INTO products (name, description, image)
      VALUES ($1, $2, $3) returning id",
      [name, description, image]
    ).to_a.first
   
    variation.each do |key, value|
      content = key['content']
      price = key['price']
      
      # product_variationテーブルにデータを保存
      client.exec_params(
        "INSERT INTO product_variation (content, price, product_id)
        VALUES ($1, $2, $3)",
        [content, price, product['id']]
      )
    end
    # エラーがなければトランザクションを終了し、DBに反映
    client.exec("COMMIT")
    return redirect "/admin/products"
  rescue
    # エラーがあれば処理を全てキャンセルする
    client.exec("ROLLBACK")
    return redirect "/admin/products/new"
  end
end

# 商品一覧
get '/admin/products' do
  @products = client.exec_params("SELECT * FROM products;").to_a
  return erb :'admin/products'
end

# 商品詳細
get '/admin/product/:id' do
  product_id = params[:id]
  @product = client.exec_params("SELECT * FROM products WHERE id = $1",
    [product_id]
  ).to_a.first
  @variation = client.exec_params("SELECT * FROM product_variation WHERE product_id = $1",
    [product_id]
  ).to_a
  return erb :'admin/product'
end

# 注文一覧
get '/admin/orders' do
  return erb :'admin/orders'
end

# 注文詳細
get '/admin/order/:id' do
  return erb :'admin/order'
end

