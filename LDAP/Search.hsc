{- -*- Mode: haskell; -*-
Haskell LDAP Interface
Copyright (C) 2005 John Goerzen <jgoerzen@complete.org>

This code is under a 3-clause BSD license; see COPYING for details.
-}

{- |
   Module     : LDAP.Search
   Copyright  : Copyright (C) 2005 John Goerzen
   License    : BSD

   Maintainer : John Goerzen,
   Maintainer : jgoerzen@complete.org
   Stability  : provisional
   Portability: portable

LDAP Searching

Written by John Goerzen, jgoerzen\@complete.org
-}

module LDAP.Search (SearchAttributes
                   )
where

import LDAP.Utils
import LDAP.Types
import LDAP.Data
import Foreign

#include <ldap.h>

{- | Defines what attributes to return with the search result. -}
data SearchAttributes =
  LDAPNoAttrs                   -- ^ No attributes
  LDAPAllUserAttrs              -- ^ User attributes only
  LDAPAttrList [String]         -- ^ User-specified list

sa2sl :: SearchAttributes -> [String]
sa2sl LDAPNoAttrs = [ #{const_str LDAP_NO_ATTRS} ]
sa2sl LDAPAllUserAttrs = [ #{const_str LDAP_ALL_USER_ATTRIBUTES} ]
sa2sl (LDAPAttrList x) = x

data LDAPEntry = LDAPEntry 
    {LEDN :: String             -- ^ Distinguished Name for this object
    ,LEAttrs :: [(String, [String])] -- ^ Map from attribute names to values
    }
    deriving (Eq, Show)

ldapSearch :: LDAP              -- ^ LDAP connection object
           -> Maybe String      -- ^ Base DN for search, if any
           -> LDAPScope         -- ^ Scope of the search
           -> Maybe String      -- ^ Filter to be used (none if Nothing)
           -> SearchAttributes  -- ^ Desired attributes in result set
           -> Bool              -- ^ If True, exclude attribute values (return types only)
           -> IO [LDAPEntry]

ldapSearch ld base scope filter attrs attrsonly =
  withLDAPPtr ld (\cld ->
  withMString base (\cbase ->
  withMString filter (\cfilter ->
  withCStringArr (sa2sl attrs) (\cattrs ->
  do msgid <- checkLEn1 "ldapSearch" ld $
              ldap_search cld cbase (fromIntegral $ fromEnum scope)
                          cfilter cattrs (fromBool attrsonly)
     res1 <- ldap_1result ld msgid
     withForeignPtr res1 (\cres1 ->
      do felm <- ldap_first_entry cld cres1
         if felm == nullPtr
            then return []
            else do cdn <- ldap_get_dn cld felm -- FIXME: check null
                    dn <- peekCString cdn
                    ldap_memfree cdn
                    attrs <- getattrs ld felm
                    return $ LDAPEntry {LEDN = dn, LEAttrs = attrs}
     
  ))))

data BerElement

getattrs :: LDAP -> (Ptr LDAPMessage) -> IO [(String, [String])]
getattrs ld lmptr =
    withLDAPPtr ld (\cld -> alloca (f cld))
    where f cld (ptr::Ptr (Ptr BerElement)) =
              do cstr <- ldap_first_attribute cld lmptr ptr
                 if cstr == nullPtr
                    then return []
                    else do str <- peekCString
                            ldap_memfree cstr
                            bptr <- peek ptr
                            values <- getvalues cld lmptr str
                            nextitems <- getnextitems cld lmptr bptr
                            return $ (str, values):nextitems

getnextitems :: Ptr CLDAP -> Ptr LDAPMessage -> Ptr BerElement 
             -> IO [(String, [String])]
getnextitems cld lmptr bptr =
    do cstr <- ldap_next_attribute cld lmptr bptr
       if cstr == nullPtr
          then return []
          else do str <- peekCString
                  ldap_memfree cstr
                  values <- getvalues cld lmptr str
                  nextitems <- getnextitems cld lmptr bptr
                  return $ (str, values):nextitems

data Berval
bv2str :: Ptr Berval -> IO String
bv2str bptr = 
    do len <- (#{peek berval, bv_len}) bptr
       cstr <- (#{peek berval, bv_val}) bptr
       peekCStringLen (cstr, len)

getvalues :: LDAPPtr -> Ptr LDAPMessage -> String -> IO [String]
getvalues cld clm attr =
    withCString attr (\cattr ->
    do berarr <- ldap_get_values_len cld clm cattr
       finally procberarr ldap_value_free_len
    )

procberarr :: Ptr (Ptr Berval) -> IO [String]
procberarr pbv =
    do bvl <- peekArray0 nullPtr pbv
       mapM bv2str bvl

foreign import ccall unsafe "ldap.h ldap_get_values_len"
  ldap_get_values_len :: LDAPPtr -> Ptr LDAPMessage -> CString -> IO (Ptr (Ptr Berval))

foreign import ccall unsafe "ldap.h ldap_value_free_len"
  ldap_value_free_len :: Ptr (Ptr Berval) -> IO ()

foreign import ccall unsafe "ldap.h ldap_search"
  ldap_search :: LDAPPtr -> CString -> LDAPInt -> CString -> Ptr CString ->
                 LDAPInt -> IO LDAPInt

foreign import ccall unsafe "ldap.h ldap_first_entry"
  ldap_first_entry :: LDAPPtr -> Ptr LDAPMessage -> IO (Ptr LDAPMessage)

foreign import ccall unsafe "ldap.h ldap_first_attribute"
  ldap_first_attribute :: LDAPPtr -> Ptr LDAPMessage -> Ptr (Ptr BerElement) 
                       -> IO CString

foreign import ccall unsafe "ldap.h ldap_next_attribute"
  ldap_next_attribute :: LDAPPtr -> Ptr LDAPMessage -> Ptr BerElement
                       -> IO CString