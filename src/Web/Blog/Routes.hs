{-# LANGUAGE OverloadedStrings #-}

module Web.Blog.Routes (routes) where

import Web.Scotty
import Web.Blog.Views
import Web.Blog.Render
import Web.Blog.SiteData (SiteData)
import Web.Blog.Database
import qualified Text.Blaze.Html5 as H
import Data.Text
import Control.Monad.IO.Class
import qualified Database.Persist as D
import qualified Database.Persist.Postgresql as DP
import Web.Blog.Models
import Data.Monoid

routes :: SiteData -> ScottyM ()
routes siteData = do
  let pageData' = pageData siteData
  
  get "/" $ 
    html "Hello World!"

  get "/entry/:entryId" $ do
    eId <- param "entryId"

    e <- liftIO $ runDB $
      DP.get $ DP.Key $ DP.PersistInt64 (fromIntegral (eId :: Int))
    
    let
      view =
        case e of
          Just entry -> viewEntry entry
          Nothing -> return mempty

    siteRenderActionLayout (view) $ 
      pageData' { pageDataTitle = Just "Entry" }


siteRenderActionLayout :: SiteRender H.Html -> PageData -> ActionM ()
siteRenderActionLayout view = siteRenderAction (viewLayout view)

