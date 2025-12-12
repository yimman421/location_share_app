// src/main.js
// Appwrite Function: Korean Address Converter

// ✅ Appwrite SDK import 제거 (Node.js 18에서는 기본 제공)
const fetch = require('node-fetch');

// 도로명주소 API 키 (환경변수)
const JUSO_API_KEY = process.env.JUSO_API_KEY || 'U01TX0FVVEgyMDI1MTIwMzE2MTczNzExNjUzMDQ=';

module.exports = async ({ req, res, log, error }) => {
  try {
    // CORS 헤더
    const headers = {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    // OPTIONS 요청 처리
    if (req.method === 'OPTIONS') {
      return res.json({ ok: true }, 200, headers);
    }

    // 요청 파라미터 추출
    let query = '';
    
    try {
      // body가 문자열인 경우 파싱
      if (typeof req.body === 'string') {
        const bodyData = JSON.parse(req.body);
        query = bodyData.query || '';
      } else {
        query = req.body?.query || '';
      }
    } catch (e) {
      // query 파라미터로도 시도
      query = req.query?.query || '';
    }
    
    if (!query || query.trim().length === 0) {
      return res.json({
        success: false,
        error: '검색어가 필요합니다',
      }, 400, headers);
    }

    log(`📍 주소 검색 요청: "${query}"`);

    // 1️⃣ 도로명주소 API 호출
    const jusoUrl = `https://business.juso.go.kr/addrlink/addrLinkApi.do?` +
      `currentPage=1` +
      `&countPerPage=10` +
      `&keyword=${encodeURIComponent(query)}` +
      `&confmKey=${JUSO_API_KEY}` +
      `&resultType=json`;

    log(`🌐 도로명주소 API 요청`);

    const jusoResponse = await fetch(jusoUrl);
    const jusoData = await jusoResponse.json();

    log(`✅ 도로명주소 API 응답 받음`);

    // 2️⃣ 응답 검증
    if (!jusoData.results || !jusoData.results.juso || jusoData.results.juso.length === 0) {
      log(`⚠️  도로명주소 API 결과 없음`);
      return res.json({
        success: false,
        error: '주소를 찾을 수 없습니다',
        query: query,
      }, 404, headers);
    }

    // 3️⃣ 결과 가공
    const addresses = jusoData.results.juso.map(item => ({
      roadAddr: item.roadAddr,
      roadAddrPart1: item.roadAddrPart1,
      roadAddrPart2: item.roadAddrPart2,
      jibunAddr: item.jibunAddr,
      engAddr: item.engAddr,
      zipNo: item.zipNo,
      siNm: item.siNm,
      sggNm: item.sggNm,
      emdNm: item.emdNm,
      liNm: item.liNm,
      rn: item.rn,
      bdNm: item.bdNm,
      searchQuery: item.roadAddrPart1 || item.roadAddr,
    }));

    log(`✅ 변환 성공: ${addresses.length}개 주소`);

    // 4️⃣ Nominatim 좌표 검색 (첫 번째 결과만)
    let coordinates = null;
    
    if (addresses.length > 0) {
      const searchAddr = addresses[0].searchQuery;
      log(`🗺️  Nominatim 검색: "${searchAddr}"`);
      
      try {
        const nominatimUrl = `http://vranks.iptime.org:8080/nominatim/search?` +
          `q=${encodeURIComponent(searchAddr)}` +
          `&format=json` +
          `&limit=1`;

        const nominatimResponse = await fetch(nominatimUrl, {
          headers: {
            'User-Agent': 'LocationShareApp/1.0'
          },
          timeout: 5000
        });

        const nominatimData = await nominatimResponse.json();

        if (nominatimData && nominatimData.length > 0) {
          coordinates = {
            lat: parseFloat(nominatimData[0].lat),
            lng: parseFloat(nominatimData[0].lon),
            display_name: nominatimData[0].display_name,
          };
          log(`✅ Nominatim 좌표: (${coordinates.lat}, ${coordinates.lng})`);
        } else {
          log(`⚠️  Nominatim 결과 없음`);
        }
      } catch (nominatimError) {
        error(`❌ Nominatim 오류: ${nominatimError.message}`);
      }
    }

    // 5️⃣ 최종 응답
    return res.json({
      success: true,
      query: query,
      totalCount: addresses.length,
      addresses: addresses,
      coordinates: coordinates,
    }, 200, headers);

  } catch (err) {
    error(`❌ Function 오류: ${err.message}`);
    return res.json({
      success: false,
      error: err.message,
    }, 500, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
  }
};
//tar -czvf function.tar.gz index.js package.json