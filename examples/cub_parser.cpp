bool CAirspaceContainer::LoadFromCUB(LPCSTR szFile, int &iMsgCode, int iFile)
{
  SCubHeader hdr;
  SCubItem itm;
  SCubPoint pnt;
  CCubItem *asi;
  DWORD dwRead;
  DWORD dwSizeItem, dwSizePoint;
  CFileStream *fs = new CFileStream(szFile);
  if (fs)
  {
    fs->Seek(0, SEEK_SET, NULL);
    memset(&hdr, 0, sizeof(hdr));
    fs->Read(&hdr, sizeof(hdr), NULL);
    if (hdr.Ident == IdentCUB && (hdr.IsSecured > 0 || hdr.PcByteOrder == 0))
    {
      ConvertCub(fs);
      fs->Seek(0, SEEK_SET, NULL);
      memset(&hdr, 0, sizeof(hdr));
      fs->Read(&hdr, sizeof(hdr), NULL);
      if (hdr.IsSecured == 2)
      {
        iMsgCode = ERROR_LFF_UNAUTHORIZED;
        delete fs;
        return false;
      }
    }
    delete fs;
  }
  CReadFileStream ms(szFile);
  if (!ms.IsOk())
  {
    iMsgCode = -1;
    return false;
  }
  ms.Seek(0, SEEK_SET, NULL);
  ms.Read(&hdr, sizeof(hdr), NULL);
  if (hdr.Ident == IdentCUB && hdr.IsSecured == 0 && hdr.PcByteOrder == 1 && hdr.SizeOfPoint > 1 &&
      hdr.SizeOfItem > 1)
  {
    dwSizeItem = MIN((DWORD)hdr.SizeOfItem, sizeof(SCubItem));
    dwSizePoint = MIN((DWORD)hdr.SizeOfPoint, sizeof(SCubPoint));
    for (int i = 0; i < hdr.HdrItems; i++)
    {
      ms.Seek(i * hdr.SizeOfItem + hdr.HeaderOffset, SEEK_SET, NULL);
      memset(&itm, 0, sizeof(SCubItem));
      ms.Read(&itm, dwSizeItem, &dwRead);
      if (dwRead != dwSizeItem)
      {
        return false;
      }
      asi = new CCubItem;
      asi->m_border.l = itm.Left;
      asi->m_border.r = itm.Right;
      asi->m_border.t = itm.Top;
      asi->m_border.b = itm.Bottom;
      asi->SetTimeout(itm.TimeOut);
      asi->m_style = CubStyle(itm.Style);
      asi->m_class = CubClass(itm.Style);
      asi->AutoClass();
      asi->m_MinAltStyle = CubAltStyle(itm.AltStyle & 0x0f);
      asi->m_MaxAltStyle = CubAltStyle(itm.AltStyle >> 4);
      asi->m_MinAlt = itm.MinAlt;
      asi->m_MaxAlt = itm.MaxAlt;
      asi->m_datapos = itm.Data + hdr.DataOffset;
      asi->m_iFile = iFile;
      asi->m_iIndex = i;
      asi->m_nSize = 0;
      asi->m_dLoLaScale = hdr.LoLaScale;
      asi->m_SizeOfPoint = hdr.SizeOfPoint;
      if ((itm.ExtData >> 30) == 0 && itm.ExtData != 0)
      {
        asi->m_NotamType = (eNotamType)(itm.ExtData >> 28);
        asi->m_NotamTraffic = (eNotamTraffic)((itm.ExtData >> 4) & 7);
        asi->m_NotamScope = (eNotamScope)(itm.ExtData & 0xF);
        uint16_t val;
        val = (itm.ExtData >> 23) & 0x1f;
        asi->m_NotamSubject[0] = val ? ('A' + val - 1) : '\0';
        val = (itm.ExtData >> 18) & 0x1f;
        asi->m_NotamSubject[1] = val ? ('A' + val - 1) : '\0';
        val = (itm.ExtData >> 13) & 0x1f;
        asi->m_NotamAction[0] = val ? ('A' + val - 1) : '\0';
        val = (itm.ExtData >> 8) & 0x1f;
        asi->m_NotamAction[1] = val ? ('A' + val - 1) : '\0';
        // 00TTSSSS SsssssAA AAAaaaaa 0RRRCCCC - Type, Subject; Action, tRaffic, sCope
      }
      asi->m_DaysActive = (eDaysActive)(itm.ActiveTime >> 52);
      Uint32 packed = (itm.ActiveTime >> 26) & 0x3FFFFFF;
      asi->m_ActiveFromDT = (packed == 0) ? NODATA : unpackDateTime(packed);
      packed = itm.ActiveTime & 0x3FFFFFF;
      asi->m_ActiveUpToDT = (packed == 0x3FFFFFF) ? NODATA : unpackDateTime(packed);
      double ox, oy;
      ox = asi->m_border.l;
      oy = asi->m_border.b;
      CLoLaPoint lola = {0, 0};
      ms.Seek(asi->m_datapos, SEEK_SET, NULL);
      while (1)
      {
        char cptr[64];
        int len;
        ms.Read(&pnt, dwSizePoint, &dwRead);
        if (dwRead != dwSizePoint)
          break;
        if ((DWORD)hdr.SizeOfPoint != dwSizePoint)
          ms.Seek(hdr.SizeOfPoint - dwSizePoint, SEEK_CUR, NULL);
        if (pnt.flag & 0x40)
        {
          if (pnt.flag & 0x3f)
          {
            memset(cptr, 0, sizeof(cptr));
            ms.Read(cptr, pnt.flag & 0x3f, NULL);
            asi->m_csName = cptr;
            asi->m_csName.MakeUTF8();
          }
          else
          {
            asi->m_csName.Empty();
          }
          // reading frequency
          ms.Read(&pnt, dwSizePoint, &dwRead);
          if (dwSizePoint == dwRead && (pnt.flag & 0xC0) == 0xC0)
          {
            asi->m_iFreq = pnt.freq;
            if (pnt.flag & 0x3f)
            {
              memset(cptr, 0, sizeof(cptr));
              ms.Read(cptr, pnt.flag & 0x3f, NULL);
              asi->m_csFreqName = cptr;
              asi->m_csFreqName.MakeUTF8();
            }
            else
            {
              asi->m_csFreqName.Empty();
            }
            ms.Read(&pnt, dwSizePoint, &dwRead);
          }
          while (dwSizePoint == dwRead && pnt.flag == 0xA0)
          {
            switch (pnt.id)
            {
            case cdiICAO:
              if (pnt.b3 > 0)
              {
                memset(asi->m_ICAO, 0, sizeof(asi->m_ICAO));
                ms.Read(asi->m_ICAO, MIN(sizeof(asi->m_ICAO), pnt.b3), NULL);
              }
              break;
            case cdiFreq2:
              asi->m_iFreq2 = (int)pnt.b1 << 16 | (int)pnt.b2 << 8 | (int)pnt.b3;
              break;
            case cdiClassExcRmk:
              len = (int)pnt.b2 << 8 | (int)pnt.b3;
              asi->m_classExcRmk.Empty();
              if (len > 0)
              {
                LPSTR str = asi->m_classExcRmk.GetBuffer(len);
                memset(str, 0, len);
                ms.Read(str, len, NULL);
                asi->m_classExcRmk.ReleaseBuffer(len);
                asi->m_classExcRmk.MakeUTF8();
              }
              break;
            case cdiRemarks:
              len = (int)pnt.b2 << 8 | (int)pnt.b3;
              asi->m_Remarks.Empty();
              if (len > 0)
              {
                LPSTR str = asi->m_Remarks.GetBuffer(len);
                memset(str, 0, len);
                ms.Read(str, len, NULL);
                asi->m_Remarks.ReleaseBuffer(len);
                asi->m_Remarks.MakeUTF8();
              }
              break;
            case cdiIdent:
              len = (int)pnt.b3;
              asi->m_Ident.Empty();
              if (len > 0)
              {
                LPSTR str = asi->m_Ident.GetBuffer(len);
                memset(str, 0, len);
                ms.Read(str, len, NULL);
                asi->m_Ident.ReleaseBuffer(len);
                asi->m_Ident.MakeUTF8();
              }
              break;
            case cdiInserted:
            {
              Uint32 timeHigh = (Uint32)pnt.b1 << 24 | (Uint32)pnt.b2 << 16 |
                                (Uint32)pnt.b3 << 8;
              Uint8 timeLow = 0;
              ms.Read(&timeLow, 1, NULL);
              asi->m_NotamInsertDT = unpackDateTime(timeHigh | (Uint32)timeLow);
            }
            break;
            }
            ms.Read(&pnt, dwSizePoint, &dwRead);
          }
          break;
        }
        else if (pnt.flag == 0x81)
        {
          ox = ox + pnt.x * asi->m_dLoLaScale;
          oy = oy + pnt.y * asi->m_dLoLaScale;
        }
        else if (pnt.flag == 0x01)
        {
          lola.lo = pnt.x * asi->m_dLoLaScale + ox;
          lola.la = pnt.y * asi->m_dLoLaScale + oy;
          asi->m_nSize++;
        }
        else
        {
          .gitignore break;
        }
      }
      if (asi->m_nSize > 0)
        Add(asi);
      UNLOCKRELEASE(asi, LOCKWRITE);
    }
    DISPLAY_LOCKS(this);
    DISPLAY_REFS(this, 1);
    return true;
  }
lSafeExit:
  iMsgCode = -2;
  return false;
}